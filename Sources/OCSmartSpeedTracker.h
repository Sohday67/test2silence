//
//  OCSmartSpeedTracker.h
//  YTLiteSkipSilence
//
//  Tracks how much time Smart Speed has saved the user, mirroring Overcast's:
//    - smartSpeedTotalSavings           (cumulative)
//    - smartSpeedSavingsSinceLastSync   (per-session, flushed on sync)
//    - timelineSilenceSkippedSamples    (256-element int64 array used for the
//                                        visual timeline overlay in Overcast)
//    - isSmartSpeedBypassed / didChangeSmartSpeedBypassed
//        (music-detection toggles bypass on/off)
//

#ifndef OCSmartSpeedTracker_h
#define OCSmartSpeedTracker_h

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const OCSmartSpeedBypassDidChangeNotification;
extern NSNotificationName const OCSmartSpeedSavingsDidChangeNotification;

@interface OCSmartSpeedTracker : NSObject

// Cumulative savings (persisted via OCSettings).
@property (nonatomic, readonly) NSTimeInterval smartSpeedTotalSavings;
@property (nonatomic, readonly) NSTimeInterval smartSpeedSavingsSinceLastSync;

// Mirrors Overcast's isSmartSpeedBypassed property. When YES, Smart Speed is
// NOT being applied (because music is playing, user paused, etc.).
@property (nonatomic, readonly) BOOL isSmartSpeedBypassed;

// Mirrors Overcast's timelineSilenceSkippedSamples — a 256-element int64 array
// where each bucket represents samples skipped in a 1-second window. Used by
// the timeline overlay to render silence-skipped regions. After reading, the
// tracker auto-advances the write head.
@property (nonatomic, readonly) const int64_t *timelineSilenceSkippedSamples;
@property (nonatomic, readonly) NSUInteger    timelineSilenceSkippedSamplesCount;

+ (instancetype)shared;

// Mark a region [start, end) as silence-skipped (Skip Silence mode). The
// duration is added to both savings counters and to the timeline array.
- (void)recordSkippedInterval:(CMTime)start to:(CMTime)end baselineRate:(float)baseline;

// Mark a region as smart-speed-played (faster than baseline). The savings
// equal (dur - dur/ratio), the time the user would have spent at baseline.
- (void)recordSmartSpeedInterval:(CMTime)start to:(CMTime)end
                       baselineRate:(float)baseline
                    silenceSkipRate:(float)skipRate;

// Bypass toggle (music detection). Posts OCSmartSpeedBypassDidChangeNotification.
- (void)setBypassed:(BOOL)bypassed reason:(NSString *)reason;

// Flush per-session savings to disk.
- (void)flush;

// Reset total + per-session savings.
- (void)resetSavings;

@end

NS_ASSUME_NONNULL_END

#endif /* OCSmartSpeedTracker_h */
