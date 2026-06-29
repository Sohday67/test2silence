//
//  OCSmartSpeedTracker.m
//  YTLiteSkipSilence
//

#import "OCSmartSpeedTracker.h"
#import "OCSettings.h"
#import "OCLog.h"

NSNotificationName const OCSmartSpeedBypassDidChangeNotification  = @"OCSmartSpeedBypassDidChange";
NSNotificationName const OCSmartSpeedSavingsDidChangeNotification = @"OCSmartSpeedSavingsDidChange";

// Match Overcast's `[256{?="timelineSilenceSkippedSamples"q}]` array.
#define kOCSTimelineBuckets 256

@interface OCSmartSpeedTracker () {
    @public
    int64_t _timelineSamples[kOCSTimelineBuckets];
}
@property (nonatomic, assign) NSUInteger writeHead;
@property (nonatomic, assign) BOOL isSmartSpeedBypassed;
@property (nonatomic, strong) NSTimer *flushTimer;
@end

@implementation OCSmartSpeedTracker

+ (instancetype)shared {
    static OCSmartSpeedTracker *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [OCSmartSpeedTracker new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        memset(_timelineSamples, 0, sizeof(_timelineSamples));
        _writeHead = 0;
        _isSmartSpeedBypassed = NO;

        // Persist savings every 5 seconds.
        _flushTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                       target:self
                                                     selector:@selector(flush)
                                                     userInfo:nil
                                                      repeats:YES];
    }
    return self;
}

- (NSTimeInterval)smartSpeedTotalSavings {
    return [OCSettings shared].smartSpeedTotalSavings;
}

- (NSTimeInterval)smartSpeedSavingsSinceLastSync {
    return [OCSettings shared].smartSpeedSavingsSinceLastSync;
}

- (const int64_t *)timelineSilenceSkippedSamples {
    return _timelineSamples;
}

- (NSUInteger)timelineSilenceSkippedSamplesCount {
    return kOCSTimelineBuckets;
}

#pragma mark - Recording

- (void)recordSkippedInterval:(CMTime)start to:(CMTime)end baselineRate:(float)baseline {
    NSTimeInterval dur = CMTimeGetSeconds(CMTimeSubtract(end, start));
    if (dur <= 0) return;
    // Skipping this region means the user does NOT spend `dur` seconds listening.
    // Savings = dur (the entire silent region is gone).
    NSTimeInterval saved = dur;
    [self addSavings:saved];
    [self pushTimelineSamples:(int64_t)(dur * (double)(baseline > 0 ? baseline : 1.0) * 48000.0)];
    OCLogD(SmartSpeed, @"skip interval saved %.3fs [%.3f→%.3f]", saved, CMTimeGetSeconds(start), CMTimeGetSeconds(end));
}

- (void)recordSmartSpeedInterval:(CMTime)start to:(CMTime)end
                       baselineRate:(float)baseline
                    silenceSkipRate:(float)skipRate {
    NSTimeInterval dur = CMTimeGetSeconds(CMTimeSubtract(end, start));
    if (dur <= 0 || baseline <= 0 || skipRate <= baseline) return;
    // Time the user would have spent at baseline: dur * (skipRate / baseline).
    // Time they actually spent: dur.
    // Savings = dur * (skipRate / baseline) - dur = dur * ((skipRate - baseline) / baseline)
    NSTimeInterval saved = dur * ((skipRate - baseline) / baseline);
    [self addSavings:saved];
    [self pushTimelineSamples:(int64_t)(saved * (double)baseline * 48000.0)];
    OCLogD(SmartSpeed, @"smart-speed interval saved %.3fs [%.3f→%.3f] %.2fx/%.2fx",
           saved, CMTimeGetSeconds(start), CMTimeGetSeconds(end), skipRate, baseline);
}

- (void)addSavings:(NSTimeInterval)saved {
    if (saved <= 0) return;
    OCSettings *s = [OCSettings shared];
    s.smartSpeedTotalSavings         = s.smartSpeedTotalSavings + saved;
    s.smartSpeedSavingsSinceLastSync = s.smartSpeedSavingsSinceLastSync + saved;
    [[NSNotificationCenter defaultCenter] postNotificationName:OCSmartSpeedSavingsDidChangeNotification
                                                        object:self
                                                      userInfo:@{@"delta": @(saved)}];
}

- (void)pushTimelineSamples:(int64_t)samples {
    _timelineSamples[_writeHead] = samples;
    _writeHead = (_writeHead + 1) % kOCSTimelineBuckets;
}

- (void)setBypassed:(BOOL)bypassed reason:(NSString *)reason {
    if (_isSmartSpeedBypassed == bypassed) return;
    _isSmartSpeedBypassed = bypassed;
    [[NSNotificationCenter defaultCenter] postNotificationName:OCSmartSpeedBypassDidChangeNotification
                                                        object:self
                                                      userInfo:@{@"bypassed": @(bypassed),
                                                                  @"reason": reason ?: @""}];
    OCLogI(SmartSpeed, @"bypass %@ — %@", bypassed ? @"YES" : @"NO", reason ?: @"(no reason)");
}

- (void)flush {
    [[OCSettings shared] synchronize];
}

- (void)resetSavings {
    OCSettings *s = [OCSettings shared];
    s.smartSpeedTotalSavings = 0;
    s.smartSpeedSavingsSinceLastSync = 0;
    memset(_timelineSamples, 0, sizeof(_timelineSamples));
    _writeHead = 0;
    [self flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:OCSmartSpeedSavingsDidChangeNotification
                                                        object:self];
}

@end
