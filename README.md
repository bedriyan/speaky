<p align="center">
  <img src="app-icon.png" width="128" height="128" alt="Speakink Icon">
</p>

<h1 align="center">Speakink</h1>

<p align="center">
  <strong>Lightweight macOS voice-to-text app</strong><br>
  Record speech via global hotkey, transcribe locally or via cloud, paste at cursor.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-black?style=flat-square" alt="macOS 15+">
  <img src="https://img.shields.io/badge/swift-6.0-F5A622?style=flat-square" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT License">
</p>

<p align="center">
  <a href="https://github.com/bedriyan/speakink/releases/latest"><strong>Download Latest Release</strong></a>
</p>

---

## Download

| Build | Architecture | Default Engine |
|-------|-------------|----------------|
| [**Speakink-Apple-Silicon.dmg**](https://github.com/bedriyan/speakink/releases/latest/download/Speakink-1.0.0-Apple-Silicon.dmg) | Apple Silicon (M1/M2/M3/M4) | Parakeet V3 |
| [**Speakink-Intel.dmg**](https://github.com/bedriyan/speakink/releases/latest/download/Speakink-1.0.0-Intel.dmg) | Intel (x86_64) | Whisper Medium Q5 |

## Features

- **Global Hotkey** — Press a modifier key or custom shortcut to start/stop recording from anywhere
- **Push-to-Talk & Hands-Free** — Hold to record, or tap to toggle recording on/off
- **Local Transcription** — Whisper and Parakeet models run fully on-device, your audio never leaves your Mac
- **Cloud Transcription** — Groq Whisper API for fast cloud-based transcription (free tier available)
- **Auto-Paste** — Transcribed text is automatically pasted at your cursor position
- **Smart Text Cleanup** — Removes filler words (um, uh, like), fixes capitalization and spacing
- **Custom Dictionary** — Define word replacements to fix common misheard terms
- **Dynamic Island Overlay** — Amber-themed notch animation with live waveform during recording
- **Dashboard** — Usage statistics with today and all-time transcription counts, minutes, and words
- **Transcription History** — Full history with search, date grouping, copy, re-transcribe, and Reveal in Finder
- **Transcribe Audio Files** — Drag and drop or browse audio files for transcription
- **Auto-Cleanup** — Configurable automatic deletion of old recordings and transcriptions
- **Dual Platform** — Native builds for both Apple Silicon and Intel Macs

## Supported Models

| Model | Type | Size | Speed | Accuracy | Platform |
|-------|------|------|-------|----------|----------|
| Parakeet V3 | Local (CoreML) | ~494MB | 5/5 | 5/5 | Apple Silicon only |
| Whisper Medium Q5 | Local (whisper.cpp) | ~539MB | 3/5 | 4/5 | Both |
| Groq Whisper | Cloud (API) | — | 5/5 | 5/5 | Both |
| Whisper Medium | Local (whisper.cpp) | ~1.5GB | 2/5 | 4/5 | Both |
| Whisper Small | Local (whisper.cpp) | ~466MB | 4/5 | 3/5 | Both |
| Whisper Small Q5 | Local (whisper.cpp) | ~190MB | 4/5 | 3/5 | Both |
| Whisper Base | Local (whisper.cpp) | ~142MB | 5/5 | 2/5 | Both |
| Whisper Base Q5 | Local (whisper.cpp) | ~60MB | 5/5 | 2/5 | Both |
| Whisper Tiny | Local (whisper.cpp) | ~75MB | 5/5 | 1/5 | Both |
| Whisper Large v1 | Local (whisper.cpp) | ~2.9GB | 1/5 | 4/5 | Both |
| Whisper Large v2 | Local (whisper.cpp) | ~2.9GB | 1/5 | 5/5 | Both |

You can also import custom `.bin` Whisper models.

## Build from Source

Speakink uses [xcodegen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project.

```bash
# Install xcodegen
brew install xcodegen

# Build and run (universal binary)
./build.sh

# Or build for a specific architecture
./build.sh silicon    # Apple Silicon only
./build.sh intel      # Intel only
./build.sh separate   # Both + DMGs in release/
```

## Dependencies

| Package | Purpose |
|---------|---------|
| [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) | whisper.cpp Swift wrapper |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Global hotkey |
| [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) | Notch overlay animation |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Parakeet engine (Apple Silicon) |

## Architecture

```
Speakink/
├── AppState.swift              # Central state manager (@Observable, @MainActor)
├── Models/
│   ├── Transcription.swift     # SwiftData model
│   ├── TranscriptionModel.swift # Model metadata + arch-aware availability
│   ├── UsageStatistics.swift   # Cumulative usage counters
│   ├── WordReplacement.swift   # Custom dictionary entries
│   └── Settings.swift          # App preferences (UserDefaults)
├── Services/
│   ├── AudioRecorder.swift     # AVAudioEngine → 16kHz mono WAV
│   ├── AudioControlService.swift # System volume control
│   ├── PasteService.swift      # CGEvent-based Cmd+V paste
│   ├── HotkeyManager.swift     # Global keyboard shortcuts
│   ├── ModelManager.swift      # Model download + cache
│   ├── TextCleanupService.swift # Filler word removal
│   ├── CleanupService.swift    # Auto-cleanup old transcriptions
│   └── Transcription/
│       ├── TranscriptionEngine.swift # Protocol
│       ├── WhisperEngine.swift       # Local (whisper.cpp)
│       ├── ParakeetEngine.swift      # Local (CoreML, arm64)
│       └── GroqEngine.swift          # Cloud (Groq API)
├── Utilities/
│   ├── Constants.swift         # Centralized magic numbers
│   ├── Theme.swift             # Colors + corner radius constants
│   ├── KeychainHelper.swift    # Secure API key storage
│   ├── AudioFileLoader.swift   # Shared audio loading utility
│   ├── AudioLevelMonitor.swift # Real-time audio levels
│   └── WAVWriter.swift         # WAV file encoding
└── Views/
    ├── MainWindow/             # Dashboard, History, AI Models, Dictionary, Settings
    ├── Onboarding/             # First-launch setup flow
    ├── Overlay/                # Dynamic Island recording UI
    ├── MenuBar/                # Menu bar controls
    └── Shared/                 # Reusable components
```

## Requirements

- macOS 15.0+ (Sequoia)
- Microphone permission
- Accessibility permission (for auto-paste)

## License

MIT
