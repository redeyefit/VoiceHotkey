# VoiceHotkey

Push-to-talk voice transcription for macOS. Hold **Right Command** to record, release to transcribe and auto-paste.

## How It Works

1. Hold Right Command — starts recording via microphone
2. Release — transcribes speech locally using [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
3. Text is copied to clipboard and auto-pasted into the active app

~400ms transcription latency. Runs invisibly in the background with no dock icon or menu bar.

## Requirements

- macOS 13+
- Apple Silicon (arm64)
- [Homebrew](https://brew.sh) dependencies:

```bash
brew install sox whisper-cpp
```

## Build & Install

```bash
git clone https://github.com/redeyefit/VoiceHotkey.git
cd VoiceHotkey
./build.sh
```

Then grant permissions in **System Settings > Privacy & Security**:
- **Accessibility** — add `~/Applications/VoiceHotkey.app`
- **Input Monitoring** — add `~/Applications/VoiceHotkey.app`

## Auto-Start on Login

```bash
./install-service.sh
```

## Uninstall

```bash
./uninstall.sh
```

## Configuration

Edit `VoiceHotkey/main.swift` to change:

| Setting | Default | Description |
|---------|---------|-------------|
| Trigger key | Right Command | `event.keyCode == 0x36` |
| Min hold time | 0.4s | Filters out quick Cmd shortcuts |
| Whisper model | `small.en` | Trade accuracy vs speed |
| Beam size | 8 | Higher = more accurate, slower |

Available whisper models (install with `brew install whisper-cpp`):

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| `ggml-tiny.en.bin` | 74MB | ~190ms | Good |
| `ggml-base.en.bin` | 141MB | ~300ms | Better |
| `ggml-small.en.bin` | 465MB | ~400ms | Best balance |

## How It's Built

Single-file Swift app compiled with `swiftc`. No Xcode project needed.

- **Recording:** sox (CoreAudio capture, 16kHz mono WAV)
- **Transcription:** whisper-cli (on-device, no API calls)
- **Auto-paste:** CGEvent synthetic Cmd+V keystroke
- **Process:** NSApplication with `.accessory` policy (invisible background app)

## License

MIT
