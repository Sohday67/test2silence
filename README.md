# YTLiteSkipSilence

> A YTLite extension that ports Overcast's "Skip Silence" and "Smart Speed"
> audio engines to YouTube playback on iOS.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: iOS 15+](https://img.shields.io/badge/Platform-iOS%2015%2B-blue.svg)](https://developer.apple.com/ios/)
[![Arch: arm64](https://img.shields.io/badge/Arch-arm64-lightgrey.svg)](#)
[![Theos](https://img.shields.io/badge/Built%20with-Theos-orange.svg)](https://theos.dev)
[![Build](https://github.com/Sohday67/test2silence/actions/workflows/build.yml/badge.svg)](https://github.com/Sohday67/test2silence/actions/workflows/build.yml)

---

## Features

- **Skip Silence** — automatically jumps past sustained silent regions in any
  YouTube video, matching Overcast's `skipSilences` behavior.
- **Smart Speed** — plays silent regions at up to 3× the baseline rate (Overcast's
  `useSmartSpeed` mode), then restores the normal rate when speech resumes.
- **Music Detection** — uses Apple's `SoundAnalysis` framework with the same
  `SNClassifierIdentifierVersion1` classifier identifier Overcast uses, so
  Smart Speed is automatically bypassed during music.
- **Voice Boost** *(optional)* — dynamic-range compression targeting podcast
  loudness (-16 LUFS) with a high-shelf voice-intelligibility boost, mirroring
  Overcast's `OCVoiceBoostConfiguration`.
- **Time-Saved HUD** — an in-player pill showing cumulative Smart Speed
  savings, just like Overcast's "Smart Speed has saved you an extra …" banner.
- **Tunable via YTLite settings panel or Settings.app** — silence threshold
  (dBFS), minimum silence duration, silence skipping speed, music-detection
  toggle, HUD toggle, verbose logging, and a "reset savings" button.

## How it works

```
YouTube AVPlayer ──► MTAudioProcessingTap ──► OCSilenceDetector (vDSP RMS)
                                              │
                                              ├─► SkipSilences mode → AVPlayer.seekToTime(end+0.4s)
                                              │
                                              └─► SmartSpeed mode   → AVPlayer.rate = silenceSkippingSpeed
                                                                      │
                                                                      └─► on silence end → AVPlayer.rate = baseline
                                                                                          + OCSmartSpeedTracker.recordSmartSpeedInterval

                          ┌──► OCAudioClassifier (SoundAnalysis SNClassifierIdentifierVersion1)
                          │       │
                          │       └─► "music" → OCSmartSpeedTracker.setBypassed:YES
                          │
                          └─► "speech" → setBypassed:NO → Smart Speed resumes
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full diagram and
[`docs/OVERCAST_PORTING_NOTES.md`](docs/OVERCAST_PORTING_NOTES.md) for a
class-by-class porting table.

## Requirements

| Tool / Runtime | Version |
|---|---|
| iOS | 15.0 or newer (required for `SNClassifierIdentifierVersion1`) |
| Architecture | arm64 (works on arm64e devices via MobileSubstrate's compat shim) |
| [Theos](https://theos.dev) | latest |
| iPhone SDK | iPhoneOS16.5.sdk (from [theos/sdks](https://github.com/theos/sdks)) |
| YouTube | any version compatible with [YTLite](https://github.com/dayanch96/YTLite) 5.0+ |
| YTLite | 5.0 or newer (optional — without it, only the Settings.app panel works) |
| jailbreak | Dopamine / Palera1n / Serotonin (rootless) |

## Building

```bash
# 1. Clone
git clone https://github.com/Sohday67/test2silence.git
cd test2silence

# 2. Make sure Theos is set up
export THEOS=~/theos
git clone --recursive https://github.com/theos/theos.git $THEOS

# 3. Install the iPhone SDK
git clone --depth 1 https://github.com/theos/sdks.git /tmp/sdks
cp -R /tmp/sdks/iPhoneOS16.5.sdk $THEOS/sdks/

# 4. Build the .deb
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

# 5. Install (via SSH to your jailbroken device)
make install
```

The build produces `packages/com.ytlite.skipsilence_1.0.0_iphoneos-arm64.deb`.

## Installation

### From the .deb

1. Transfer `packages/com.ytlite.skipsilence_1.0.0_iphoneos-arm.deb` to your
   device.
2. Install via Filza or `dpkg -i`.
3. Respring.
4. Open **YouTube** — playback now has Skip Silence / Smart Speed active
   with default settings.
5. Open **Settings → YTLiteSkipSilence** (or the YTLite panel inside
   YouTube) to customize.

### From a YTLite extension repository

Add this repo's URL to your package manager (Sileo / Zebra):

```
https://your-fork.github.io/YTLiteSkipSilence/
```

Then install the **YTLiteSkipSilence** package.

## Settings

| Setting | Key | Default | Range | Notes |
|---|---|---|---|---|
| Enabled | `OCSSEnabled` | YES | bool | Master switch |
| Skip Silence | `OCSSSkipSilences` | YES | bool | Jump past silence |
| Smart Speed | `OCSSUseSmartSpeed` | NO | bool | Play silence faster |
| Music Detection | `OCSSUseSmartSpeedMusicDetection` | YES | bool | Bypass SS during music |
| Silence Threshold | `OCSSSilenceThresholdDBFS` | -40 | -60 … -20 dBFS | Lower = stricter |
| Minimum Silence | `OCSSMinimumSilenceDuration` | 0.5 | 0.1 … 2.0 s | Below this, ignored |
| Silence Skipping Speed | `OCSSSilenceSkippingSpeed` | 2.0 | 1.25 … 3.0× | Smart Speed rate |
| Voice Boost | `OCSSUseVoiceBoost` | NO | bool | Optional |
| Standard Preset | `OCSSStandardVoiceBoostConfiguration` | YES | bool | Use factory VB preset |
| Show Time-Saved HUD | `OCSSShowTimeSavedHUD` | YES | bool | In-player pill |
| Verbose Logging | `OCSSVerboseLogging` | NO | bool | Console |

All settings live in `NSUserDefaults` suite `com.ytlite.skipsilence` so they
can be read/written from any of the three UIs (YTLite panel, Settings.app,
or in-player HUD).

## Files

```
YTLiteSkipSilence/
├── Makefile
├── control
├── YTLiteSkipSilence.plist            # Theos filter (com.google.ios.youtube)
├── YTLiteSkipSilenceExtension.plist   # YTLite extension descriptor
├── Tweak.x                            # Logos hooks into YouTube
├── Sources/
│   ├── OCLog.{h,m}                    # Categorized os_log wrapper
│   ├── OCSettings.{h,m}               # Typed NSUserDefaults wrapper
│   ├── OCAudioPlaybackSpeed.{h,m}     # Port of OCAudioPlaybackSpeed
│   ├── OCVoiceBoostConfiguration.{h,m}# Port of OCVoiceBoostConfiguration
│   ├── OCSilenceDetector.{h,m}        # RMS-based silence detection (audio side of OCAudioClassifier)
│   ├── OCAudioClassifier.{h,m}        # SoundAnalysis speech/music classifier (OCAudioClassifier proper)
│   ├── OCSmartSpeedTracker.{h,m}      # smartSpeedTotalSavings, timelineSilenceSkippedSamples[256], bypass state
│   ├── OCSkipSilenceEngine.{h,m}      # Principal class — owns AVPlayer tap, state machine, mirrors OCAudioPlayer API
│   └── MTAudioProcessingTapStubs.m    # Private API declarations for the AVPlayer audio tap
├── Preferences/
│   ├── Root.plist                     # PreferenceLoader bundle (Settings.app)
│   ├── RootPane.plist
│   ├── control                        # Debian control for the settings bundle
│   └── YTLiteSkipSilenceSettings.x    # Standalone UIKit settings VC (YTLite extension panel)
├── Assets/                            # Icon assets (placeholders)
├── docs/
│   ├── ARCHITECTURE.md
│   └── OVERCAST_PORTING_NOTES.md
└── Package/                           # Theos build output (.gitkeep)
```

## Compatibility

- ✅ YouTube stable (TestFlight and App Store builds)
- ✅ YTLite 5.0+ (loads the extension via `YTLiteSkipSilenceExtension.plist`)
- ✅ Works without YTLite — settings then live in Settings.app via the
  `Preferences/` bundle (PreferenceLoader required)
- ⚠️ YouTube Reborn / Cercube — not officially supported, but the hooks target
  the YouTube base classes (`YTPlayerView`, `MLPlaybackController`,
  `YTInlinePlayerBarView`) so should work. Disable the Cercube/Reborn
  playback-speed features to avoid conflicts.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| No silence skipping | Ensure **Enabled = YES** in settings. Confirm audio is actually playing (tap fires only on live audio). |
| Smart Speed too aggressive | Raise **Silence Threshold** (e.g., -35 dBFS) or increase **Minimum Silence** (e.g., 0.8 s). |
| Smart Speed ruins music | Enable **Music Detection**. If still bad, raise confidence threshold in `OCSkipSilenceEngine.m` (`result.confidence > 0.6`). |
| Voice Boost distorts | Disable Voice Boost, or lower the master gain in `OCVoiceBoostConfiguration.standardConfiguration`. |
| HUD overlaps scrubber | The HUD is anchored at the top-left of `YTInlinePlayerBarView`. If your YouTube version uses a different layout, adjust the frame in `Tweak.x`. |
| Logs not visible | Set `OCSSVerboseLogging = YES`, then capture with `idevicesyslog` or Console.app. Filter by `com.ytlite.skipsilence.*`. |

## Algorithm Attribution

The silence-detection and Smart Speed state-machine logic in this extension is
a clean-room reimplementation based on the public Objective-C / Swift symbol
surface of the Overcast for iOS binary. The original algorithm and class
design (`OCAudioClassifier`, `OCAudioPlayer`, `OCAudioPlaybackSpeed`,
`OCVoiceBoostConfiguration`, `OCSmartSpeedIntent`, etc.) are the work of
Marco Arment and the Overcast team. This project reproduces the behavior for
personal use inside YouTube via YTLite; it does not redistribute any of
Overcast's compiled code or assets. See [LICENSE](LICENSE) for full
attribution.

## License

MIT — see [LICENSE](LICENSE).
