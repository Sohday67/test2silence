//
//  OCSilenceDetector.h
//  YTLiteSkipSilence
//
//  Real-time silence detector — the audio-side counterpart of Overcast's
//  `OCAudioClassifier` (Swift symbol _TtC7OCAudio17OCAudioClassifier).
//
//  Overcast's classifier performs two tasks:
//    1. Per-window silence/non-silence classification using an RMS dBFS
//       threshold (the `silenceThreshold:` parameter on
//       -[OCAudioPlayer seekToNextSilenceWithMinimumSampleDuration:threshold:]
//       and -[OCAudioPlayer timestampOfNearestSilenceBetweenStartTime:endTime:silenceThreshold:]).
//    2. Speech / music discrimination via Apple's SoundAnalysis framework
//       (SNClassifierIdentifierVersion1) — used by Smart Speed's
//       `useSmartSpeedMusicDetection` switch to bypass silence-skipping
//       while music is playing.
//
//  This class is responsible for (1). Speech/music detection lives in
//  `OCAudioClassifier.h/.m` which we ship as a thin wrapper around the same
//  SoundAnalysis classifier identifier Overcast uses.
//

#ifndef OCSilenceDetector_h
#define OCSilenceDetector_h

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

// A single silence region detected on the audio stream.
@interface OCSilenceRegion : NSObject
@property (nonatomic, assign) CMTime startTime;
@property (nonatomic, assign) CMTime endTime;
@property (nonatomic, assign) float  averageDBFS;
@property (nonatomic, assign) float  peakDBFS;
+ (instancetype)regionWithStart:(CMTime)s end:(CMTime)e avg:(float)avg peak:(float)p;
- (NSTimeInterval)duration;
@end

// Detector delegate — receives per-window classification.
@protocol OCSilenceDetectorDelegate <NSObject>
@optional
- (void)silenceDetectorDidDetectSilenceStart:(CMTime)startTime avgDBFS:(float)avg;
- (void)silenceDetectorDidDetectSilenceEnd:(CMTime)endTime avgDBFS:(float)avg duration:(NSTimeInterval)dur;
- (void)silenceDetectorDidProcessWindowAtTime:(CMTime)t rmsDBFS:(float)rms isSilent:(BOOL)silent;
@end

@interface OCSilenceDetector : NSObject

// Configuration (mirrors Overcast's silenceThreshold: and minimumSampleDuration:).
@property (nonatomic, assign) float          silenceThresholdDBFS; // default -40
@property (nonatomic, assign) NSTimeInterval minimumSilenceDuration; // default 0.5s
@property (nonatomic, assign) float          sampleRate;            // 48000 default
@property (nonatomic, assign) NSUInteger     channels;              // 2 default

// Windowing — Overcast uses ~20ms analysis windows internally.
@property (nonatomic, assign) NSTimeInterval analysisWindow;        // default 0.02s
@property (nonatomic, assign) NSTimeInterval lookaheadBuffer;       // default 0.4s

@property (nonatomic, weak) id<OCSilenceDetectorDelegate> delegate;

// Rolling list of detected silence regions (most recent at end). Capped at
// 256 entries. Used by OCSkipSilenceEngine to find the nearest silence when
// the user calls seekToNearestSilence... selectors.
@property (nonatomic, readonly) NSArray<OCSilenceRegion *> *recentRegions;

- (instancetype)initWithSampleRate:(float)sampleRate channels:(NSUInteger)channels;

// Push a buffer of PCM audio into the detector. This is the entry point used
// by the MTAudioProcessingTap installed on AVPlayer's audio mix.
- (void)processPCMBuffer:(AVAudioPCMBuffer *)buffer atTime:(CMTime)time;

// One-shot classification — used when seeking with
// `seekToNearestSilenceBetweenStartTime:endTime:`.
- (nullable OCSilenceRegion *)findNearestSilenceInRegions:(NSArray<OCSilenceRegion *> *)regions
                                                fromTime:(CMTime)startTime
                                                  toTime:(CMTime)endTime;

// Reset state (called when the user scrubs / a new video loads).
- (void)reset;

// Statistics
@property (nonatomic, readonly) NSUInteger totalWindowsProcessed;
@property (nonatomic, readonly) NSUInteger totalSilenceWindowsDetected;

@end

NS_ASSUME_NONNULL_END

#endif /* OCSilenceDetector_h */
