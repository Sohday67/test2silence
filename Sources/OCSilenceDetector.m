//
//  OCSilenceDetector.m
//  YTLiteSkipSilence
//
//  RMS-based silence detector. Uses Accelerate (vDSP) for the per-window
//  RMS computation so it is fast enough to run inside an MTAudioProcessingTap
//  callback on the audio render thread.
//

#import "OCSilenceDetector.h"
#import "OCLog.h"
#import <Accelerate/Accelerate.h>

@implementation OCSilenceRegion

+ (instancetype)regionWithStart:(CMTime)s end:(CMTime)e avg:(float)avg peak:(float)p {
    OCSilenceRegion *r = [OCSilenceRegion new];
    r.startTime = s;
    r.endTime = e;
    r.averageDBFS = avg;
    r.peakDBFS = p;
    return r;
}

- (NSTimeInterval)duration {
    return CMTimeGetSeconds(CMTimeSubtract(self.endTime, self.startTime));
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<OCSilenceRegion [%.3f → %.3f] avg=%.1f peak=%.1f>",
            CMTimeGetSeconds(self.startTime), CMTimeGetSeconds(self.endTime),
            self.averageDBFS, self.peakDBFS];
}
@end

@interface OCSilenceDetector ()
@property (nonatomic, assign) NSUInteger totalWindowsProcessed;
@property (nonatomic, assign) NSUInteger totalSilenceWindowsDetected;

// Rolling state
@property (nonatomic, assign) BOOL   inSilenceRun;
@property (nonatomic, assign) CMTime silenceRunStart;
@property (nonatomic, assign) float  silenceRunAccumDBFS;
@property (nonatomic, assign) NSUInteger silenceRunWindowCount;
@property (nonatomic, assign) float  silenceRunPeakDBFS;
@property (nonatomic, strong) NSMutableArray<OCSilenceRegion *> *recentRegions;
@end

@implementation OCSilenceDetector

- (instancetype)initWithSampleRate:(float)sampleRate channels:(NSUInteger)channels {
    if ((self = [super init])) {
        _silenceThresholdDBFS    = -40.0f;
        _minimumSilenceDuration  = 0.5;
        _sampleRate              = sampleRate > 0 ? sampleRate : 48000.0f;
        _channels                = channels > 0 ? channels : 2;
        _analysisWindow          = 0.02;  // 20 ms
        _lookaheadBuffer         = 0.4;
        _inSilenceRun            = NO;
        _recentRegions           = [NSMutableArray arrayWithCapacity:64];
    }
    return self;
}

#pragma mark - Processing

// Convert a float32 PCM buffer (interleaved or deinterleaved) to mono RMS.
static float OCComputeRMSMono(AVAudioPCMBuffer *buf) {
    if (!buf || !buf.audioBufferList) return 0;
    AudioBufferList *abl = buf.audioBufferList;
    UInt32 nChannels = abl->mNumberBuffers;
    if (nChannels == 0) return 0;
    UInt32 frames = buf.frameLength;
    if (frames == 0) return 0;

    // Average across channels.
    double sumSq = 0.0;
    for (UInt32 c = 0; c < nChannels; c++) {
        const float *ch = (const float *)abl->mBuffers[c].mData;
        if (!ch) continue;
        int n = (int)frames;
        float rmsChannel;
        vDSP_svesq(ch, 1, &rmsChannel, n);          // sum of squares
        sumSq += (double)rmsChannel;
    }
    double meanSq = sumSq / ((double)frames * (double)nChannels);
    return (float)sqrt(MAX(meanSq, 1e-20));
}

static float OCComputePeakMono(AVAudioPCMBuffer *buf) {
    if (!buf || !buf.audioBufferList) return 0;
    AudioBufferList *abl = buf.audioBufferList;
    UInt32 nChannels = abl->mNumberBuffers;
    UInt32 frames = buf.frameLength;
    float peak = 0;
    for (UInt32 c = 0; c < nChannels; c++) {
        const float *ch = (const float *)abl->mBuffers[c].mData;
        if (!ch) continue;
        float localPeak;
        vDSP_maxmgv(ch, 1, &localPeak, (int)frames);
        if (localPeak > peak) peak = localPeak;
    }
    return peak;
}

static inline float OCRMStoDBFS(float rms) {
    if (rms <= 1e-9f) return -120.0f;
    return 20.0f * log10f(rms);
}

- (void)processPCMBuffer:(AVAudioPCMBuffer *)buffer atTime:(CMTime)time {
    if (!buffer || buffer.frameLength == 0) return;

    float rms  = OCComputeRMSMono(buffer);
    float peak = OCComputePeakMono(buffer);
    float rmsDB  = OCRMStoDBFS(rms);
    float peakDB = OCRMStoDBFS(peak);

    BOOL silent = (rmsDB < _silenceThresholdDBFS);

    self.totalWindowsProcessed += 1;
    if (silent) self.totalSilenceWindowsDetected += 1;

    // Per-window callback (optional, used by debug HUD).
    if ([_delegate respondsToSelector:@selector(silenceDetectorDidProcessWindowAtTime:rmsDBFS:isSilent:)]) {
        [_delegate silenceDetectorDidProcessWindowAtTime:time rmsDBFS:rmsDB isSilent:silent];
    }

    if (silent) {
        if (!_inSilenceRun) {
            _inSilenceRun = YES;
            _silenceRunStart = time;
            _silenceRunAccumDBFS = 0.0f;
            _silenceRunWindowCount = 0;
            _silenceRunPeakDBFS = -120.0f;
            if ([_delegate respondsToSelector:@selector(silenceDetectorDidDetectSilenceStart:avgDBFS:)]) {
                [_delegate silenceDetectorDidDetectSilenceStart:time avgDBFS:rmsDB];
            }
        }
        _silenceRunAccumDBFS += rmsDB;
        _silenceRunWindowCount += 1;
        if (peakDB > _silenceRunPeakDBFS) _silenceRunPeakDBFS = peakDB;
    } else {
        [self endSilenceRunAtTime:time];
    }
}

- (void)endSilenceRunAtTime:(CMTime)time {
    if (!_inSilenceRun) return;
    _inSilenceRun = NO;
    NSTimeInterval dur = CMTimeGetSeconds(CMTimeSubtract(time, _silenceRunStart));
    if (dur < _minimumSilenceDuration) {
        // Too short — ignore.
        return;
    }
    float avg = _silenceRunWindowCount ? _silenceRunAccumDBFS / (float)_silenceRunWindowCount : -120.0f;
    OCSilenceRegion *r = [OCSilenceRegion regionWithStart:_silenceRunStart
                                                       end:time
                                                       avg:avg
                                                      peak:_silenceRunPeakDBFS];
    [_recentRegions addObject:r];
    if (_recentRegions.count > 256) {
        [_recentRegions removeObjectAtIndex:0];
    }
    if ([_delegate respondsToSelector:@selector(silenceDetectorDidDetectSilenceEnd:avgDBFS:duration:)]) {
        [_delegate silenceDetectorDidDetectSilenceEnd:time avgDBFS:avg duration:dur];
    }
    OCLogD(SkipSilence, @"silence region: %@ duration=%.3fs avg=%.1fdB peak=%.1fdB",
           r, dur, avg, _silenceRunPeakDBFS);
}

- (nullable OCSilenceRegion *)findNearestSilenceInRegions:(NSArray<OCSilenceRegion *> *)regions
                                                fromTime:(CMTime)startTime
                                                  toTime:(CMTime)endTime {
    NSTimeInterval s = CMTimeGetSeconds(startTime);
    NSTimeInterval e = CMTimeGetSeconds(endTime);
    if (e <= s) return nil;

    OCSilenceRegion *best = nil;
    NSTimeInterval bestDelta = 1e9;
    for (OCSilenceRegion *r in regions) {
        NSTimeInterval rStart = CMTimeGetSeconds(r.startTime);
        NSTimeInterval rEnd   = CMTimeGetSeconds(r.endTime);
        if (rEnd < s || rStart > e) continue;
        NSTimeInterval mid = (rStart + rEnd) * 0.5;
        NSTimeInterval d = fabs(mid - (s + e) * 0.5);
        if (d < bestDelta) { bestDelta = d; best = r; }
    }
    return best;
}

- (void)reset {
    _inSilenceRun = NO;
    _silenceRunWindowCount = 0;
    _silenceRunAccumDBFS = 0.0f;
    _silenceRunPeakDBFS = -120.0f;
    [_recentRegions removeAllObjects];
}

@end
