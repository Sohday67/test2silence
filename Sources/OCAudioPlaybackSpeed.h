//
//  OCAudioPlaybackSpeed.h
//  YTLiteSkipSilence
//
//  Faithful Objective-C port of Overcast's `OCAudioPlaybackSpeed` class
//  (Swift symbol: _TtC7OCAudio20OCAudioPlaybackSpeed).
//
//  Overcast exposes three speed values on this class:
//    - baselineSpeed           (the user's chosen normal-speed rate)
//    - playbackSpeed           (the rate currently applied to the player)
//    - silenceSkippingSpeed    (the rate temporarily applied during silence
//                                when Smart Speed is enabled)
//
//  We keep the same API surface so any future Overcast code can be dropped
//  in without modification.
//

#ifndef OCAudioPlaybackSpeed_h
#define OCAudioPlaybackSpeed_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCAudioPlaybackSpeed : NSObject <NSCopying, NSSecureCoding>

// Default 1.0x. Stored as a raw multiplier (0.25x … 3.0x).
@property (nonatomic, assign) float rate;

// Convenience constructors.
+ (instancetype)standardSpeed;          // 1.0x
+ (instancetype)speedWithRate:(float)rate;

- (instancetype)initWithRate:(float)rate NS_DESIGNATED_INITIALIZER;

// Returns the rate clamped to YouTube's accepted AVPlayer range.
- (float)clampedRate;

@end

NS_ASSUME_NONNULL_END

#endif /* OCAudioPlaybackSpeed_h */
