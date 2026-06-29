//
//  OCSettings.h
//  YTLiteSkipSilence
//
//  Typed accessor layer over NSUserDefaults.
//
//  Key names mirror the property keys found in the Overcast binary
//  (skipSilences, silenceSkippingSpeed, useSmartSpeed, useSmartSpeedMusicDetection,
//  useVoiceBoost, voiceBoostConfiguration, standardVoiceBoostConfiguration,
//  isSmartSpeedBypassed, isSmartSpeedEnabled, isVoiceBoostEnabled, etc.)
//  so that anyone familiar with Overcast's settings model can find the
//  equivalent knob here.
//

#ifndef OCSettings_h
#define OCSettings_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Equivalent to Overcast's TB,N,V_skipSilences / V_useSmartSpeed / V_useVoiceBoost
// property declarations, but stored in NSUserDefaults so the user can change
// them at runtime via the YTLite settings panel.
extern NSString * const OCSettingsKeyEnabled;
extern NSString * const OCSettingsKeySkipSilences;          // skipSilences
extern NSString * const OCSettingsKeyUseSmartSpeed;         // useSmartSpeed
extern NSString * const OCSettingsKeyUseSmartSpeedMusicDetection; // useSmartSpeedMusicDetection
extern NSString * const OCSettingsKeyUseVoiceBoost;         // useVoiceBoost
extern NSString * const OCSettingsKeyStandardVoiceBoostConfiguration; // standardVoiceBoostConfiguration
extern NSString * const OCSettingsKeySilenceThresholdDBFS;  // silenceThreshold:
extern NSString * const OCSettingsKeyMinimumSilenceDuration; // minimumSampleDuration:
extern NSString * const OCSettingsKeySilenceSkippingSpeed;  // silenceSkippingSpeed
extern NSString * const OCSettingsKeyBaselineSpeed;         // baselineSpeed
extern NSString * const OCSettingsKeyVoiceBoostTargetLUFS;  // targetLUFS
extern NSString * const OCSettingsKeyVoiceBoostCompressorThreshold;
extern NSString * const OCSettingsKeyVoiceBoostDeEsserThreshold;
extern NSString * const OCSettingsKeySmartSpeedTotalSavings; // smartSpeedTotalSavings
extern NSString * const OCSettingsKeySmartSpeedSavingsSinceLastSync; // smartSpeedSavingsSinceLastSync
extern NSString * const OCSettingsKeyShowTimeSavedHUD;
extern NSString * const OCSettingsKeyVerboseLogging;

@interface OCSettings : NSObject

+ (instancetype)shared;

// Underlying NSUserDefaults (suite: com.ytlite.skipsilence). Exposed so the
// settings UI and Logos hooks can read/write raw keys directly.
@property (nonatomic, readonly, strong) NSUserDefaults *defaults;

// Master switch — does the extension do anything at all?
@property (nonatomic, assign) BOOL enabled;

// Mirrors Overcast's TB,N,V_skipSilences property.
@property (nonatomic, assign) BOOL skipSilences;

// Mirrors Overcast's TB,N,V_useSmartSpeed property.
@property (nonatomic, assign) BOOL useSmartSpeed;

// Mirrors Overcast's TB,N,V_useSmartSpeedMusicDetection property.
@property (nonatomic, assign) BOOL useSmartSpeedMusicDetection;

// Mirrors Overcast's TB,N,V_useVoiceBoost property.
@property (nonatomic, assign) BOOL useVoiceBoost;

// Mirrors Overcast's TB,N,V_standardVoiceBoostConfiguration property.
@property (nonatomic, assign) BOOL standardVoiceBoostConfiguration;

// silenceThreshold: parameter of
//   -[OCAudioPlayer seekToNextSilenceWithMinimumSampleDuration:threshold:]
//   -[OCAudioPlayer timestampOfNearestSilenceBetweenStartTime:endTime:silenceThreshold:]
// Stored as dBFS, default -40 (Overcast default).
@property (nonatomic, assign) float silenceThresholdDBFS;

// minimumSampleDuration: parameter — minimum length (seconds) of sustained
// silence before the engine acts. Default 0.5s.
@property (nonatomic, assign) NSTimeInterval minimumSilenceDuration;

// silenceSkippingSpeed — wraps an OCAudioPlaybackSpeed in Overcast. We expose
// the raw multiplier here (1.25x … 3.0x). Default 2.0x.
@property (nonatomic, assign) float silenceSkippingSpeed;

// baselineSpeed — normal playback rate. Default 1.0x.
@property (nonatomic, assign) float baselineSpeed;

// Voice Boost targets (mirrors OCVoiceBoostConfiguration fields).
@property (nonatomic, assign) NSInteger voiceBoostTargetLUFS;          // default -16
@property (nonatomic, assign) float voiceBoostCompressorThreshold;     // dBFS
@property (nonatomic, assign) float voiceBoostDeEsserThreshold;        // dBFS

// smartSpeedTotalSavings / smartSpeedSavingsSinceLastSync — persisted
// across launches so the user can see how much time we have saved them.
@property (nonatomic, assign) NSTimeInterval smartSpeedTotalSavings;
@property (nonatomic, assign) NSTimeInterval smartSpeedSavingsSinceLastSync;

// UI
@property (nonatomic, assign) BOOL showTimeSavedHUD;
@property (nonatomic, assign) BOOL verboseLogging;

// Convenience — true if either Skip Silences or Smart Speed is enabled.
- (BOOL)isFeatureActive;

// Reset SmartSpeed savings (called from settings).
- (void)resetSmartSpeedSavings;

// Synchronize changes.
- (void)synchronize;

@end

NS_ASSUME_NONNULL_END

#endif /* OCSettings_h */
