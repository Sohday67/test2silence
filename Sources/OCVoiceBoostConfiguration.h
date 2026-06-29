//
//  OCVoiceBoostConfiguration.h
//  YTLiteSkipSilence
//
//  Faithful Objective-C port of Overcast's `OCVoiceBoostConfiguration` class.
//
//  Overcast's Voice Boost is a dynamic-range compression pipeline targeting a
//  fixed LUFS loudness target. The configuration object carries:
//    - targetLUFS                  (target integrated loudness)
//    - compressorThreshold         (dBFS, when compressor kicks in)
//    - deEsserThreshold            (dBFS, when de-esser kicks in)
//    - standardVoiceBoostConfiguration flag (presets vs. custom)
//
//  In this YTLite port we ship the configuration object plus an `applyToEngine:`
//  method (mirroring Overcast's `applyToVoiceBoost:` selector) that wires the
//  parameters into an AVAudioEngine as ParametricEQ + DynamicsProcessor + high-
//  shelf boost nodes. Voice Boost itself is optional and off by default; the
//  default-settings preset matches Overcast's `standardVoiceBoostConfiguration`
//  preset.
//

#ifndef OCVoiceBoostConfiguration_h
#define OCVoiceBoostConfiguration_h

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCVoiceBoostConfiguration : NSObject <NSCopying, NSSecureCoding>

// LUFS — Overcast default -16 (podcast loudness target).
@property (nonatomic, assign) NSInteger targetLUFS;

// Compressor threshold in dBFS (Overcast default -24).
@property (nonatomic, assign) float compressorThreshold;

// De-esser threshold in dBFS (Overcast default -30).
@property (nonatomic, assign) float deEsserThreshold;

// Master gain applied to the post-boost signal (dB).
@property (nonatomic, assign) float masterGainDB;

// Mirrors Overcast's `standardVoiceBoostConfiguration` BOOL — when YES this
// configuration reflects the factory preset rather than a user-customized one.
@property (nonatomic, assign) BOOL isStandardPreset;

+ (instancetype)standardConfiguration;
+ (instancetype)configurationWithTargetLUFS:(NSInteger)lufs
                         compressorThreshold:(float)compressor
                            deEsserThreshold:(float)deEsser
                                  masterGain:(float)gain;

- (instancetype)initWithTargetLUFS:(NSInteger)lufs
                compressorThreshold:(float)compressor
                   deEsserThreshold:(float)deEsser
                         masterGain:(float)gain
                  isStandardPreset:(BOOL)standard NS_DESIGNATED_INITIALIZER;

// Equivalent of Overcast's `applyToVoiceBoost:` selector. Wires this
// configuration into the given AVAudioEngine chain by attaching / configuring
// the relevant AVAudioUnit nodes. Returns the effect node chain (input →
// deEsser → compressor → EQ → masterGain → output) or nil on failure.
- (nullable AVAudioMixerNode *)applyToEngine:(AVAudioEngine *)engine
                                  sourceNode:(AVAudioNode *)sourceNode;

@end

NS_ASSUME_NONNULL_END

#endif /* OCVoiceBoostConfiguration_h */
