# Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                              YouTube (host app)                        │
│                                                                        │
│   ┌─────────────────────┐    ┌────────────────────────────────────┐    │
│   │   MLPlaybackCtrl    │    │   YTPlayerView                     │    │
│   │   (Logos hook)      │───▶│   (Logos hook → AVPlayer)          │    │
│   └─────────────────────┘    └──────────────┬─────────────────────┘    │
│                                             │                          │
│                                             ▼                          │
│                              ┌───────────────────────────┐            │
│                              │       AVPlayer            │            │
│                              │  .currentItem.audioMix    │            │
│                              └─────────────┬─────────────┘            │
│                                            │                          │
└────────────────────────────────────────────┼──────────────────────────┘
                                             │
                  ┌──────────────────────────┼──────────────────────────┐
                  │                          ▼                          │
                  │     ┌───────────────────────────────────────┐       │
                  │     │  MTAudioProcessingTap                 │       │
                  │     │  (MediaToolbox, post-EFI)             │       │
                  │     │  process callback on audio render     │       │
                  │     │  thread                                │       │
                  │     └─────────────┬─────────────────────────┘       │
                  │                   │                                 │
                  │                   ▼                                 │
                  │     ┌───────────────────────────────────────┐       │
                  │     │   OCSkipSilenceEngine (principal)     │       │
                  │     │   - attachToPlayer:                   │       │
                  │     │   - reloadSettings                    │       │
                  │     │   - seekToNextSilence...:threshold:   │       │
                  │     └────┬────────────┬─────────────┬───────┘       │
                  │          │            │             │               │
                  │          ▼            ▼             ▼               │
                  │   ┌──────────┐  ┌────────────┐  ┌─────────────┐     │
                  │   │ Silence  │  │ Audio      │  │ SmartSpeed  │     │
                  │   │ Detector │  │ Classifier │  │ Tracker     │     │
                  │   │ (vDSP)   │  │ (SoundAna) │  │ (256-bkt)   │     │
                  │   └────┬─────┘  └─────┬──────┘  └──────┬──────┘     │
                  │        │              │                │            │
                  │        ▼              ▼                ▼            │
                  │  silence-end   music/speech label   savings+=dur   │
                  │  event         → bypass toggle       → flush        │
                  │        │                                            │
                  │        ▼                                            │
                  │   if (skipSilences) → AVPlayer.seekToTime(end+0.4)  │
                  │   if (useSmartSpeed) → AVPlayer.rate = skipRate     │
                  │                                                        │
                  │   YTLiteSkipSilence.dylib                              │
                  └────────────────────────────────────────────────────────┘

   ┌───────────────────────────────┐
   │   Settings persistence        │
   │   NSUserDefaults suite:       │
   │   com.ytlite.skipsilence      │
   └───────────────┬───────────────┘
                   │
   ┌───────────────┴───────────────┐
   │  Settings UI                  │
   │  - YTLite extension panel     │
   │    (OCSkipSilenceSettings     │
   │     Controller)               │
   │  - Settings.app bundle        │
   │    (PreferenceLoader)         │
   │  - In-player HUD              │
   │    (YTInlinePlayerBarView)    │
   └───────────────────────────────┘
```

## Component responsibilities

| Component | Ported from Overcast | Responsibility |
|---|---|---|
| `OCSkipSilenceEngine` | `OCAudioPlayer` | Owns the AVPlayer tap and the silence/smart-speed state machine |
| `OCSilenceDetector` | `OCAudioClassifier` (audio side) | Per-window RMS dBFS classification; emits silence start/end events |
| `OCAudioClassifier` | `OCAudioClassifier` (SoundAnalysis side) | Speech/music discrimination via `SNClassifierIdentifierVersion1` |
| `OCAudioPlaybackSpeed` | `OCAudioPlaybackSpeed` | Wraps a playback rate (baselineSpeed / silenceSkippingSpeed) |
| `OCVoiceBoostConfiguration` | `OCVoiceBoostConfiguration` | Target-LUFS + compressor + EQ preset |
| `OCSmartSpeedTracker` | `OCAudioPlayer`'s savings + timeline tracking | `smartSpeedTotalSavings`, `smartSpeedSavingsSinceLastSync`, `timelineSilenceSkippedSamples[256]`, `isSmartSpeedBypassed` |
| `OCSettings` | `OCAudioPlayer`'s settings properties | Typed NSUserDefaults wrapper |
| `OCLog` | Overcast's os_log subsystem | Categorized logging |
| `Tweak.x` | n/a | Logos hooks into YouTube's player + settings UI |
| `YTLiteSkipSilenceSettings.x` | n/a | Standalone settings view controller |
| `Preferences/Root.plist` | n/a | PreferenceLoader bundle for Settings.app |

## Data flow

1. **Player attach** — YouTube's `MLPlaybackController.setPlayerView:` is hooked. We extract the underlying `AVPlayer` from `YTPlayerView` and pass it to `[OCSkipSilenceEngine attachToPlayer:]`.

2. **Tap installation** — The engine locates the AVAssetTrack audio track, builds an `MTAudioProcessingTap`, attaches it via `AVMutableAudioMixInputParameters.audioTapProcessor`, and installs the mix on the AVPlayerItem.

3. **Per-buffer analysis** — Every audio render cycle, `MTAudioProcessingTap.process` fires. The engine:
   - Wraps the `CMAudioBufferList` into an `AVAudioPCMBuffer`.
   - Calls `OCSilenceDetector.processPCMBuffer:atTime:` which uses `vDSP_svesq` to compute RMS, converts to dBFS, and classifies as silent/non-silent.
   - If `useSmartSpeedMusicDetection` is on, also calls `OCAudioClassifier.processBuffer:atTime:` which feeds the buffer to an `SNAudioStreamAnalyzer`.

4. **Silence start** — When the detector's rolling RMS window drops below `silenceThresholdDBFS`, the engine records `smartSpeedBoostStart` and:
   - **SmartSpeed mode**: sets `AVPlayer.rate = silenceSkippingSpeed.clampedRate`.
   - **SkipSilences mode**: waits for the silence-end event.

5. **Silence end** — When RMS rises above threshold again (or audio resumes), the engine:
   - **SmartSpeed mode**: restores `AVPlayer.rate = baselineSpeed`. Calls `[tracker recordSmartSpeedInterval:...]` to compute savings as `dur * (skipRate - baseline) / baseline`.
   - **SkipSilences mode**: calls `[player seekToTime:end+lookaheadBuffer]` to jump past the silent region. Calls `[tracker recordSkippedInterval:...]` to record savings = full silent duration.

6. **Music detection** — When the SoundAnalysis classifier reports music with confidence > 0.6, `[tracker setBypassed:YES reason:@"music detected"]` is called. This posts `OCSmartSpeedBypassDidChangeNotification`. The engine listens for it and, if currently boosting, immediately restores the baseline rate.

7. **Persistence** — `OCSettings` writes to `NSUserDefaults` suite `com.ytlite.skipsilence`. `OCSmartSpeedTracker` flushes savings every 5 seconds via an `NSTimer` and on `resetSavings`.

8. **HUD** — `YTInlinePlayerBarView.layoutSubviews` is hooked to inject a `UILabel` showing the cumulative time saved (toggled by `showTimeSavedHUD`).

## Hook targets

| YouTube class | Selector | Why |
|---|---|---|
| `MLPlaybackController` | `setPlayerView:` | Detect new video / new AVPlayer |
| `YTPlayerView` | `dealloc` | Detach engine on player teardown |
| `YTInlinePlayerBarView` | `layoutSubviews` | Inject Smart Speed HUD |
| `YTLiteRootSettingsController` | `settings` | Add Skip Silence section |
| `YTSettingsCell` | `setSwitchValue:` | Persist switch changes to NSUserDefaults |
| `YTSettingsViewController` | `didTapButtonWithIdentifier:` | Handle Reset Savings button |

## Why MTAudioProcessingTap (not AVAudioEngine)?

YouTube uses `AVPlayer` (not `AVAudioEngine`) for video playback. `AVAudioEngine` cannot be inserted between an `AVPlayer` and its audio output without completely re-routing the audio through a custom engine — which would break YouTube's own audio handling, video sync, and AirPlay.

`MTAudioProcessingTap` is the official Apple-supported way to tap into `AVPlayer`'s audio pipeline. It is used by Apple's own apps (Music, Podcasts, TV) and by Overcast itself for Voice Boost. The tap receives a read-only `CMAudioBufferList` per render cycle and can pass it through unmodified (which is what we do — we don't modify the audio, only inspect it).

## Why SoundAnalysis for music detection?

Overcast uses Apple's `SNClassifierIdentifierVersion1` (the speech/music classifier shipped with the SoundAnalysis framework). We use the same identifier so the resulting labels match what Overcast's state machine expects. The classifier is loaded lazily, only when `useSmartSpeedMusicDetection` is on.
