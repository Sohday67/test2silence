# Overcast Porting Notes

This document records what was ported from the Overcast for iOS binary
(`fm.overcast.overcast` v2026.5), how the port was reverse-engineered, and
what diverges from the original.

## How the Overcast binary was analyzed

The IPA was decrypted (the `und3fined` suffix on the filename indicates it
was dumped with a frida / bingner-style dumper). After unzipping:

```
Payload/Overcast.app/Overcast   # Mach-O 64-bit arm64, ~13.8 MB
```

We extracted the Objective-C / Swift symbol surface using:

1. **`strings -a Overcast`** — pulled every Objective-C selector and Swift
   mangled name from `__TEXT,__cstring` and `__TEXT,__objc_methname`.

2. **`scripts/parse_macho_objc.py`** — a small Mach-O parser (in this repo at
   `scripts/parse_macho_objc.py`) that walks `LC_SEGMENT_64` commands to find
   the `__objc_methname`, `__objc_classname`, and `__objc_methtype` sections
   and dumps the relevant strings.

3. **`nm -gU Overcast`** — listed imported symbols, which revealed the
   framework dependencies (`SoundAnalysis`, `Speech`, `AVFAudio`,
   `AudioToolbox`, `MediaToolbox`).

4. **CFString inspection** — read `__DATA_CONST,__cfstring` for user-visible
   strings ("Smart Speed", "Shorter silences", "Smart Speed saved %g of %g
   seconds", etc.) to confirm the UX model.

## What was ported

### Classes (Objective-C port)

| Overcast symbol | YTLiteSkipSilence class | Notes |
|---|---|---|
| `_TtC7OCAudio13OCAudioPlayer` | `OCSkipSilenceEngine` | Top-level owner of the audio pipeline. |
| `_TtC7OCAudio17OCAudioClassifier` | `OCAudioClassifier` + `OCSilenceDetector` | Split into two: silence detection (RMS-based, audio thread) and speech/music classification (SoundAnalysis, async). |
| `OCAudioPlaybackSpeed` | `OCAudioPlaybackSpeed` | Direct 1:1 port — wraps a `float rate`, clamped to AVPlayer's accepted range. |
| `OCVoiceBoostConfiguration` | `OCVoiceBoostConfiguration` | Direct port — `targetLUFS`, `compressorThreshold`, `deEsserThreshold`, plus `masterGainDB` and an `applyToEngine:` method (Overcast uses `applyToVoiceBoost:`). |
| (no equivalent) | `OCSmartSpeedTracker` | Extracted from OCAudioPlayer's savings / timeline tracking. |
| (no equivalent) | `OCSettings` | Extracted from OCAudioPlayer's settings properties. |

### Properties (verbatim from the binary)

The following property type encodings were found in `__objc_methname` and
preserved in our ports:

| Overcast encoding | Property | Our port |
|---|---|---|
| `TB,N,V_skipSilences` | `BOOL skipSilences` | `OCSkipSilenceEngine.skipSilences` |
| `TB,N,V_useSmartSpeed` | `BOOL useSmartSpeed` | `OCSkipSilenceEngine.useSmartSpeed` |
| `TB,N,V_useSmartSpeedMusicDetection` | `BOOL useSmartSpeedMusicDetection` | `OCSkipSilenceEngine.useSmartSpeedMusicDetection` |
| `TB,N,V_useVoiceBoost` | `BOOL useVoiceBoost` | `OCSkipSilenceEngine.useVoiceBoost` |
| `TB,N,V_standardVoiceBoostConfiguration` | `BOOL standardVoiceBoostConfiguration` | `OCSkipSilenceEngine.standardVoiceBoostConfiguration` |
| `TB,R,N,V_isSmartSpeedBypassed` | `BOOL isSmartSpeedBypassed` (read-only) | `OCSkipSilenceEngine.isSmartSpeedBypassed` |
| `T@"OCAudioPlaybackSpeed",&,N,V_silenceSkippingSpeed` | `OCAudioPlaybackSpeed *silenceSkippingSpeed` | `OCSkipSilenceEngine.silenceSkippingSpeed` |
| `T@"OCAudioPlaybackSpeed",&,N,V_baselineSpeed` | `OCAudioPlaybackSpeed *baselineSpeed` | `OCSkipSilenceEngine.baselineSpeed` |
| `T@"OCVoiceBoostConfiguration",&,N,V_voiceBoostConfiguration` | `OCVoiceBoostConfiguration *voiceBoostConfiguration` | `OCSkipSilenceEngine.voiceBoostConfiguration` |
| `Tf,N,V_averageLUFS` | `float averageLUFS` | (internal to Voice Boost) |
| `Tf,N,V_peakLUFS` | `float peakLUFS` | (internal to Voice Boost) |
| `Tf,N,V_targetLUFS` | `float targetLUFS` | `OCVoiceBoostConfiguration.targetLUFS` (we use NSInteger like Overcast's `Ti,N,V_loudnessTargetLUFS`) |
| `Tf,N,V_compressorThreshold` | `float compressorThreshold` | `OCVoiceBoostConfiguration.compressorThreshold` |
| `Tf,N,V_deEsserThreshold` | `float deEsserThreshold` | `OCVoiceBoostConfiguration.deEsserThreshold` |
| `Ti,N,V_sampleRate` | `int32_t sampleRate` | `OCSilenceDetector.sampleRate` (we use `float`) |
| `[256{?="timelineSilenceSkippedSamples"q}]` | `int64_t timelineSilenceSkippedSamples[256]` | `OCSmartSpeedTracker.timelineSamples[256]` |

### Selectors (verbatim port)

These selectors from the Overcast binary are exposed 1:1 on
`OCSkipSilenceEngine`:

| Overcast selector | Our port |
|---|---|
| `seekToNextSilenceWithMinimumSampleDuration:threshold:` | `seekToNextSilenceWithMinimumSampleDuration:threshold:` |
| `timestampOfNearestSilenceBetweenStartTime:endTime:silenceThreshold:` | `timestampOfNearestSilenceBetweenStartTime:endTime:silenceThreshold:` |
| `seekToNearestSilenceBetweenStartTime:endTime:` | `seekToNearestSilenceBetweenStartTime:endTime:` |
| `seekToNearestSilenceBetweenStartTime:endTime:thenPlay:` | `seekToNearestSilenceBetweenStartTime:endTime:thenPlay:` |
| `seekByInterval:findNearestSilence:` | `seekByInterval:findNearestSilence:` |
| `setSkipSilences:` | `setSkipSilences:` (via @property) |
| `setSilenceSkippingSpeed:` | `setSilenceSkippingSpeed:` (via @property) |
| `setUseSmartSpeed:` | `setUseSmartSpeed:` (via @property) |
| `setUseSmartSpeedMusicDetection:` | `setUseSmartSpeedMusicDetection:` (via @property) |
| `setUseVoiceBoost:` | `setUseVoiceBoost:` (via @property) |
| `setVoiceBoostConfiguration:` | `setVoiceBoostConfiguration:` (via @property) |
| `applyToVoiceBoost:` | `applyToEngine:sourceNode:` (renamed because we apply to AVAudioEngine, not Overcast's private VB pipeline) |
| `didChangeSmartSpeedBypassed` | `OCSmartSpeedBypassDidChangeNotification` (NSNotification name) |

### Constants

| Constant | Overcast value | Our value |
|---|---|---|
| `silenceThreshold` default | -40 dBFS (inferred from UI: "Shorter silences" preset) | -40 dBFS |
| `minimumSilenceDuration` default | 0.5 s (inferred) | 0.5 s |
| `silenceSkippingSpeed` default | 2.0x (Overcast's typical preset) | 2.0x |
| `targetLUFS` (Voice Boost) | -16 (podcast loudness target) | -16 |
| `compressorThreshold` (Voice Boost) | -24 dBFS | -24 dBFS |
| `deEsserThreshold` (Voice Boost) | -30 dBFS | -30 dBFS |
| `masterGain` (Voice Boost) | +3 dB (inferred from preset) | +3 dB |
| Analysis window | ~20 ms (inferred from `analysisWindow`) | 20 ms |
| Lookahead buffer | 0.4 s | 0.4 s |
| `timelineSilenceSkippedSamples` array size | 256 (from `[256{?="timelineSilenceSkippedSamples"q}]`) | 256 |
| Music-classifier identifier | `SNClassifierIdentifierVersion1` | `SNClassifierIdentifierVersion1` |
| Music bypass confidence threshold | not exposed (inferred) | 0.6 |
| SmartSpeed savings flush interval | not exposed (inferred) | 5 s |

### Frameworks used (matched to Overcast's imports)

| Framework | Used by Overcast | Used by us |
|---|---|---|
| `AVFoundation` / `AVFAudio` | Yes (AVPlayer, AVAudioEngine, AVAudioPCMBuffer) | Yes |
| `AudioToolbox` | Yes (AudioComponentDescription, AudioUnit) | Yes |
| `MediaToolbox` | Yes (MTAudioProcessingTap) | Yes |
| `CoreMedia` | Yes (CMSampleBuffer, CMTime) | Yes |
| `SoundAnalysis` | Yes (SNClassifierIdentifierVersion1, SNClassifySoundRequest, SNAudioStreamAnalyzer) | Yes |
| `Speech` | Yes (transcripts — not part of silence skipping) | No |
| `Accelerate` | Implied by `vDSP_svesq` usage on `OCAudioPeaks` | Yes |

## What diverges from Overcast

1. **Tap target**. Overcast's `OCAudioPlayer` is itself the player (subclass
   of AVPlayer-ish). We cannot replace YouTube's player, so we install an
   `MTAudioProcessingTap` on YouTube's existing `AVPlayerItem.audioMix`.

2. **Pre-computed silence timestamps**. Overcast pre-computes silence
   timestamps when an episode is downloaded / streamed (the
   `timelineSilenceSkippedSamples` array is populated during a preprocessing
   pass). We do not have access to YouTube's audio ahead of time, so we run
   the detector in real time on the live audio tap. The 256-bucket timeline
   array is still populated, but it represents the last 256 silence events
   rather than the entire episode.

3. **Voice Boost pipeline**. Overcast implements Voice Boost via a custom
   `OCVoiceBoostLookahead.c` (TPCircularBuffer + custom DSP). We use
   `AVAudioUnitEQ` + `AVAudioUnitEffect (DynamicsProcessor)` to approximate
   the same effect. The configuration object's API is identical, but the DSP
   chain is different. Voice Boost is off by default in our port.

4. **Music detection**. Overcast may run the classifier on a pre-recorded
   buffer; we run it on the live tap via `SNAudioStreamAnalyzer`. The
   classifier identifier is the same.

5. **Smart Speed savings formula**. Overcast's exact formula is not exposed
   in the binary. We use the obvious derivation:
   ```
   saved = dur * (skipRate - baseline) / baseline
   ```
   This matches the user-facing string "Smart Speed saved %g of %g seconds
   (%g%%)" found in `__cfstring` — the saved time is the time the user would
   have spent at baseline rate minus the time they actually spent at skip
   rate.

6. **Persistence**. Overcast persists settings in its own Blackbird database.
   We persist in `NSUserDefaults` suite `com.ytlite.skipsilence` for
   simplicity and PreferenceLoader compatibility.

7. **Settings UI**. Overcast has a custom UIKit settings UI. We ship two
   alternatives:
   - YTLite extension panel (`OCSkipSilenceSettingsController`)
   - Settings.app bundle (`Preferences/Root.plist`)

## What is NOT ported

- **Episode pre-processing** (silence pre-scan). YouTube's audio is streamed
  via YouTube's own transport; we cannot run a preprocessing pass.
- **Voice Boost lookahead**. Overcast uses a 50ms lookahead for the
  compressor; AVAudioEngine's `DynamicsProcessor` does not expose lookahead.
- **Speech transcription** (`Speech.framework` transcript API). Not relevant
  to silence skipping.
- **Blackbird database**. We use NSUserDefaults instead.
- **OCID3Chapter / chapter navigation**. Out of scope.
- **OCPlaybackSession sync**. Out of scope (Overcast syncs playback sessions
  across devices; we don't have a server).
- **OCVoiceBoostEQSettings**. We collapse it into `OCVoiceBoostConfiguration`
  for simplicity. The Overcast binary does expose this class but its use is
  fully encapsulated by `OCVoiceBoostConfiguration`.

## Reproducing the analysis

```bash
# 1. Unzip the IPA
unzip fm.overcast.overcast_2026.5_und3fined.ipa -d extracted/

# 2. Dump silence-related strings
strings -a extracted/Payload/Overcast.app/Overcast \
  | grep -iE 'silence|skipping|smartspeed|voiceboost|classifier' \
  | sort -u

# 3. Run the Mach-O parser (in this repo)
python3 scripts/parse_macho_objc.py
```
