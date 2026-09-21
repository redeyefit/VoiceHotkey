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

// Snapshot/restore the clipboard so dictation doesn't clobber what the user had copied
// (e.g. a link). NSPasteboardItems READ from a pasteboard can't be re-written to it, so we
// copy each type's raw data into fresh items.
func snapshotPasteboard(_ pb: NSPasteboard) -> [NSPasteboardItem] {
    // Reading .string first FORCES lazily-promised pasteboard data to materialize. Without this,
    // item.data(forType:) can return nil for data another app hasn't rendered yet — we'd then
    // capture a dataless item that WIPES the clipboard to blank on restore (observed live).
    _ = pb.string(forType: .string)
    var saved: [NSPasteboardItem] = []
    for item in pb.pasteboardItems ?? [] {
        let copy = NSPasteboardItem()
        var gotData = false
        for type in item.types {
            if let data = item.data(forType: type) {
                copy.setData(data, forType: type)
                gotData = true
            }
        }
        // Never keep a dataless item — writing it back would clear the clipboard instead of restore it.
        if gotData { saved.append(copy) }
    }
    return saved
}

func restorePasteboard(_ pb: NSPasteboard, _ items: [NSPasteboardItem]) {
    // Nothing usable captured -> leave the clipboard as-is (holding the transcription) rather than
    // blanking it. clearContents() only when we actually have items to write back.
    guard !items.isEmpty else { return }
    pb.clearContents()
    pb.writeObjects(items)
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

                // Borrow the clipboard to deliver the transcription, then hand it back.
                // Snapshot FIRST so a link the user had copied survives dictation.
                let pasteboard = NSPasteboard.general
                let savedClipboard = snapshotPasteboard(pasteboard)

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

                // MUST wait for the target app to consume Cmd+V before restoring — restoring
                // too early makes the paste read the ORIGINAL clipboard and drop the
                // transcription. Main thread is already blocked through transcription, so a
                // synchronous wait here matches the existing design.
                usleep(200_000) // 200ms
                restorePasteboard(pasteboard, savedClipboard)
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
