import Cocoa
import CoreGraphics

// Disable stdout buffering so logs appear immediately
setbuf(stdout, nil)
setbuf(stderr, nil)

// MARK: - VoiceHotkey Push-to-Talk Daemon
// Hold Right Command to record, release to transcribe and paste

let soxPath = "/opt/homebrew/bin/sox"
let whisperPath = "/opt/homebrew/opt/whisper-cpp/bin/whisper-cli"
let modelPath = "/opt/homebrew/share/whisper-cpp/models/ggml-small.en.bin"
let logFile = "/tmp/voicehotkey.log"

var recordingProcess: Process?
var isRecording = false
var recordingStartTime: Date?
let minimumHoldSeconds: TimeInterval = 0.4  // Ignore quick Cmd taps (shortcuts)

// Log to both stdout and file (so launchd and direct-run both work)
func log(_ message: String) {
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "[\(ts)] \(message)\n"
    print(message)
    if let data = line.data(using: .utf8) {
        if let fh = FileHandle(forWritingAtPath: logFile) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: logFile, contents: data)
        }
    }
}

func audioPath() -> String {
    "/tmp/voice_ptt_\(Int(Date().timeIntervalSince1970)).wav"
}

var currentAudioFile = audioPath()

// Verify dependencies exist
func checkDependencies() -> Bool {
    let fm = FileManager.default
    var ok = true
    for (name, path) in [("sox", soxPath), ("whisper-cli", whisperPath), ("whisper model", modelPath)] {
        if !fm.fileExists(atPath: path) {
            log("MISSING: \(name) at \(path)")
            ok = false
        }
    }
    return ok
}

guard checkDependencies() else {
    log("Install missing dependencies: brew install sox whisper-cpp")
    exit(1)
}

// Clear old log on fresh start
try? "".write(toFile: logFile, atomically: true, encoding: .utf8)

log("VoiceHotkey running — hold Command to record, release to transcribe")

// Check if we have Accessibility permission
let trusted = AXIsProcessTrustedWithOptions(
    [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
)

if trusted {
    log("Accessibility: trusted")
} else {
    log("WARNING: Not trusted for Accessibility — add VoiceHotkey.app in System Settings")
}

// Monitor modifier key changes globally
NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
    let flags = event.modifierFlags

    // Right Command pressed — start recording
    // Use rawValue to detect right command specifically (0x10 = right cmd flag)
    let isRightCmd = flags.contains(.command) && (event.keyCode == 0x36)

    if isRightCmd && !isRecording {
        isRecording = true
        recordingStartTime = Date()
        currentAudioFile = audioPath()
        log("Recording...")

        recordingProcess = Process()
        recordingProcess?.executableURL = URL(fileURLWithPath: soxPath)
        recordingProcess?.arguments = [
            "-t", "coreaudio", "default",
            "-r", "16000", "-c", "1",
            currentAudioFile
        ]
        recordingProcess?.standardOutput = FileHandle.nullDevice
        recordingProcess?.standardError = FileHandle.nullDevice

        do {
            try recordingProcess?.run()
        } catch {
            log("Failed to start recording: \(error)")
            isRecording = false
        }
    }
    // Command released — stop recording and transcribe
    else if !flags.contains(.command) && isRecording {
        isRecording = false

        recordingProcess?.terminate()
        recordingProcess = nil

        let holdDuration = Date().timeIntervalSince(recordingStartTime ?? Date())

        // Skip if held less than minimum (was just a quick Cmd shortcut)
        if holdDuration < minimumHoldSeconds {
            log("Skipped (held \(String(format: "%.0f", holdDuration * 1000))ms — too short)")
            try? FileManager.default.removeItem(atPath: currentAudioFile)
            return
        }

        log("Stopped (\(String(format: "%.1f", holdDuration))s held), transcribing...")

        let file = currentAudioFile

        // Transcribe with local whisper.cpp
        let transcribe = Process()
        transcribe.executableURL = URL(fileURLWithPath: whisperPath)
        transcribe.arguments = [
            "-m", modelPath,
            "-f", file,
            "--no-prints",
            "--no-timestamps",
            "-l", "en",
            "--beam-size", "8",
            "--best-of", "5",
            "--entropy-thold", "2.8"
        ]

        let pipe = Pipe()
        transcribe.standardOutput = pipe
        transcribe.standardError = FileHandle.nullDevice

        do {
            let start = Date()
            try transcribe.run()
            transcribe.waitUntilExit()
            let elapsed = Date().timeIntervalSince(start)

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let ms = String(format: "%.0f", elapsed * 1000)

            if !text.isEmpty && text != "[BLANK_AUDIO]" {
                log("\(ms)ms -> \(text)")

                // Copy to clipboard
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)

                // Small delay to ensure clipboard is ready
                usleep(50_000) // 50ms

                // Auto-paste via CGEvent (Cmd+V)
                let src = CGEventSource(stateID: .hidSystemState)
                let vKeyCode: CGKeyCode = 0x09  // 'v' key
                if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
                   let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false) {
                    keyDown.flags = .maskCommand
                    keyUp.flags = .maskCommand
                    keyDown.post(tap: .cghidEventTap)
                    keyUp.post(tap: .cghidEventTap)
                }
            } else {
                log("\(ms)ms (no speech detected)")
            }
        } catch {
            log("Transcription failed: \(error)")
        }

        // Cleanup temp audio file
        try? FileManager.default.removeItem(atPath: file)
    }
}

// Run as a proper NSApplication so macOS recognizes us as a real app
// (prevents "not responding" and makes TCC permissions work correctly)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // No dock icon, no menu bar
app.run()
