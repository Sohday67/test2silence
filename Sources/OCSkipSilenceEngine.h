//
//  OCSkipSilenceEngine.h
//  YTLiteSkipSilence
//
//  Principal class of the YTLite extension. Owns the AVPlayer tap, the silence
//  detector, the music classifier, the Smart Speed state machine, and the
//  savings tracker. Exposes the same public API as Overcast's `OCAudioPlayer`
//  so the YTLite Tweak.x can delegate straight to it.
//
//  Mirrored Overcast selectors:
//    - seekToNextSilenceWithMinimumSampleDuration:threshold:
//    - timestampOfNearestSilenceBetweenStartTime:endTime:silenceThreshold:
//    - seekToNearestSilenceBetweenStartTime:endTime:
//    - seekToNearestSilenceBetweenStartTime:endTime:thenPlay:
//    - seekByInterval:findNearestSilence:
//
//  Mirrored Overcast properties:
//    - skipSilences, silenceSkippingSpeed, baselineSpeed
//    - useSmartSpeed, useSmartSpeedMusicDetection, isSmartSpeedBypassed
//    - useVoiceBoost, voiceBoostConfiguration, standardVoiceBoostConfiguration
//    - timelineSilenceSkippedSamples
//

#ifndef OCSkipSilenceEngine_h
#define OCSkipSilenceEngine_h

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import "OCAudioPlaybackSpeed.h"
#import "OCVoiceBoostConfiguration.h"
#import "OCSilenceDetector.h"
#import "OCAudioClassifier.h"
#import "OCSmartSpeedTracker.h"

NS_ASSUME_NONNULL_BEGIN

// YTLite extension protocol — declared by the YTLite runtime. We declare a
// local copy here so this file compiles standalone.
@protocol YTLiteExtensionProtocol <NSObject>
@optional
- (void)extensionDidActivate;
- (void)extensionDidDeactivate;
@end

@interface OCSkipSilenceEngine : NSObject <YTLiteExtensionProtocol,
                                           OCSilenceDetectorDelegate,
                                           OCAudioClassifierDelegate>

// The AVPlayer currently being managed (set by the Logos hook on YTPlayerView).
@property (nonatomic, weak, nullable) AVPlayer *player;
@property (nonatomic, strong, nullable) AVPlayerItem *playerItem;

// ---- Overcast-mirrored properties ----------------------------------------

// TB,N,V_skipSilences — when YES, sustained silence triggers a seek forward
// to the end of the silent region.
@property (nonatomic, assign) BOOL skipSilences;

// TB,N,V_useSmartSpeed — when YES, silence regions are played at
// silenceSkippingSpeed rather than skipped.
@property (nonatomic, assign) BOOL useSmartSpeed;

// TB,N,V_useSmartSpeedMusicDetection — when YES, music detection pauses
// Smart Speed for the duration of any music region.
@property (nonatomic, assign) BOOL useSmartSpeedMusicDetection;

// TB,N,V_useVoiceBoost — when YES, voice-boost processing is applied to
// the AVAudioEngine chain.
@property (nonatomic, assign) BOOL useVoiceBoost;

// TB,N,V_standardVoiceBoostConfiguration — when YES, the standard preset
// (targetLUFS=-16, comp=-24, deEss=-30, masterGain=+3) is used.
@property (nonatomic, assign) BOOL standardVoiceBoostConfiguration;

// OCAudioPlaybackSpeed wrappers (Overcast uses these directly).
@property (nonatomic, strong) OCAudioPlaybackSpeed *baselineSpeed;
@property (nonatomic, strong) OCAudioPlaybackSpeed *silenceSkippingSpeed;
@property (nonatomic, strong) OCVoiceBoostConfiguration *voiceBoostConfiguration;

// TB,R,N,V_isSmartSpeedBypassed — read-only mirror of the tracker.
@property (nonatomic, readonly) BOOL isSmartSpeedBypassed;

// 256-element int64 array, mirroring Overcast's timelineSilenceSkippedSamples.
@property (nonatomic, readonly) const int64_t *timelineSilenceSkippedSamples;
@property (nonatomic, readonly) NSUInteger timelineSilenceSkippedSamplesCount;

// SmartSpeed savings (delegated to OCSmartSpeedTracker).
@property (nonatomic, readonly) NSTimeInterval smartSpeedTotalSavings;
@property (nonatomic, readonly) NSTimeInterval smartSpeedSavingsSinceLastSync;

// ---- Engine lifecycle ------------------------------------------------------

+ (instancetype)shared;

// Called by the Logos hook when YouTube loads a new AVPlayerItem.
- (void)attachToPlayer:(AVPlayer *)player;

// Called when YouTube disposes the current player or loads a new video.
- (void)detach;

// Apply current settings (called when user toggles a switch in the settings
// panel).
- (void)reloadSettings;

// ---- Overcast-mirrored selectors ------------------------------------------

// Mirrors -[OCAudioPlayer seekToNextSilenceWithMinimumSampleDuration:threshold:]
- (BOOL)seekToNextSilenceWithMinimumSampleDuration:(NSTimeInterval)minDuration
                                         threshold:(float)thresholdDBFS;

// Mirrors -[OCAudioPlayer timestampOfNearestSilenceBetweenStartTime:endTime:silenceThreshold:]
// Returns kCMTimeInvalid if no silence region is found.
- (CMTime)timestampOfNearestSilenceBetweenStartTime:(CMTime)startTime
                                            endTime:(CMTime)endTime
                                    silenceThreshold:(float)thresholdDBFS;

// Mirrors -[OCAudioPlayer seekToNearestSilenceBetweenStartTime:endTime:]
- (BOOL)seekToNearestSilenceBetweenStartTime:(CMTime)startTime endTime:(CMTime)endTime;

// Mirrors -[OCAudioPlayer seekToNearestSilenceBetweenStartTime:endTime:thenPlay:]
- (BOOL)seekToNearestSilenceBetweenStartTime:(CMTime)startTime
                                      endTime:(CMTime)endTime
                                     thenPlay:(BOOL)play;

// Mirrors -[OCAudioPlayer seekByInterval:findNearestSilence:]
- (BOOL)seekByInterval:(NSTimeInterval)interval findNearestSilence:(BOOL)nearest;

@end

NS_ASSUME_NONNULL_END

#endif /* OCSkipSilenceEngine_h */
