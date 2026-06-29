//
//  OCSkipSilenceEngine.m
//  YTLiteSkipSilence
//
//  The engine wires together:
//
//    [AVPlayer] --(AVPlayerItem.audioMix.inputParameters[].audioTapProcessor)-->
//        MTAudioProcessingTap.process callback
//          -->  OCPCMBufferBuilder              (assembles an AVAudioPCMBuffer
//                                                 from the tap's buffer list)
//          -->  OCSilenceDetector.processPCMBuffer:atTime:
//          -->  OCAudioClassifier.processBuffer:atTime:  (only if music detect on)
//
//    On silence-end event from the detector:
//      - skipSilences mode:   compute target seek time = end + lookaheadBuffer
//                             and call AVPlayer.seekToTime
//      - useSmartSpeed mode:  set player.rate = silenceSkippingSpeed during
//                             the silent region, restore baselineSpeed when
//                             non-silence resumes
//
//    Music classifier (OCAudioClassifier) flips isSmartSpeedBypassed on/off
//    via OCSmartSpeedTracker, which Smart Speed respects.
//

#import "OCSkipSilenceEngine.h"
#import "OCSettings.h"
#import "OCLog.h"
#import <MediaToolbox/MediaToolbox.h>
#import <AVFAudio/AVFAudio.h>
#import <CoreMedia/CoreMedia.h>

// MTAudioProcessingTap private API (declared in MTAudioProcessingTapStubs.m)
typedef struct OpaqueMTAudioProcessingTap *MTAudioProcessingTapRef;
typedef enum {
    kMTAudioProcessingTapCreationFlag_PreEffects   = 1u << 0,
    kMTAudioProcessingTapCreationFlag_PostEffects  = 1u << 1,
} MTAudioProcessingTapCreationFlags;

typedef struct {
    uint32_t version;
    void *clientHandle;
    void (*init)(void *, void *, CFTypeRef, void **);
    void (*finalize)(void *);
    void (*prepare)(void *, CMItemCount);
    void (*unprepare)(void *);
    void (*process)(void *, CMItemCount, MTAudioProcessingTapRef, CMItemCount,
                    CMAudioBufferList *, CMTime *, CMTime *, void *);
} OCTapCallbacks;

extern OSStatus MTAudioProcessingTapCreate(CFAllocatorRef,
                                           const OCTapCallbacks *,
                                           MTAudioProcessingTapCreationFlags,
                                           MTAudioProcessingTapRef *) __attribute__((weak_import));

// ----------------------------------------------------------------------------
//  Tap context — passed through `tapStorage` to the process callback.
// ----------------------------------------------------------------------------
typedef struct {
    __unsafe_unretained OCSkipSilenceEngine *engine;
    AudioStreamBasicDescription             asbd;
    CMItemCount                             maxFrames;
    AVAudioFormat                          *format;
} OCTapContext;

// ----------------------------------------------------------------------------
//  PCM buffer builder — wraps a CMAudioBufferList into AVAudioPCMBuffer so
//  the silence detector / classifier can process it with vDSP.
// ----------------------------------------------------------------------------
static AVAudioPCMBuffer *OCBuildPCMBuffer(const CMAudioBufferList *bl,
                                          UInt32 frames,
                                          AVAudioFormat *format) {
    if (!bl || frames == 0 || !format) return nil;
    AVAudioPCMBuffer *buf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
                                                            frameCapacity:frames];
    if (!buf) return nil;
    buf.frameLength = frames;
    AudioBufferList dest = *buf.audioBufferList;
    for (UInt32 i = 0; i < bl->mNumberBuffers && i < dest.mNumberBuffers; i++) {
        size_t bytes = MIN(bl->mBuffers[i].mDataByteSize, dest.mBuffers[i].mDataByteSize);
        memcpy(dest.mBuffers[i].mData, bl->mBuffers[i].mData, bytes);
    }
    return buf;
}

// ----------------------------------------------------------------------------
//  Tap callbacks
// ----------------------------------------------------------------------------
static void OCTapInit(void *client, void *storage, CFTypeRef fmtDesc, void **storageOut) {
    // Nothing — context is allocated before MTAudioProcessingTapCreate and
    // passed via clientHandle.
    if (storageOut) *storageOut = storage;
}

static void OCTapFinalize(void *storage) {
    // Owned by the engine — do not free here.
}

static void OCTapPrepare(void *storage, CMItemCount maxFrames) {
    OCTapContext *c = (OCTapContext *)storage;
    if (c) c->maxFrames = maxFrames;
}

static void OCTapUnprepare(void *storage) {
    OCTapContext *c = (OCTapContext *)storage;
    if (c) c->maxFrames = 0;
}

static void OCTapProcess(void *storage, CMItemCount nFrames,
                         MTAudioProcessingTapRef tap,
                         CMItemCount nFramesOut,
                         CMAudioBufferList *blInOut,
                         CMTime *timeIn,
                         CMTime *timeOut,
                         void *refCon) {
    OCTapContext *c = (OCTapContext *)storage;
    if (c && c->engine && nFrames > 0) {
        @autoreleasepool {
            OCSkipSilenceEngine *eng = c->engine;
            [eng _processTapBufferList:blInOut frames:(UInt32)nFrames time:*timeIn format:c->format];
        }
    }
}

// ----------------------------------------------------------------------------
//  Engine
// ----------------------------------------------------------------------------
@interface OCSkipSilenceEngine ()
@property (nonatomic, strong) OCSilenceDetector   *detector;
@property (nonatomic, strong) OCAudioClassifier   *classifier;
@property (nonatomic, strong) OCSmartSpeedTracker *tracker;
@property (nonatomic, strong) OCSettings          *settings;

@property (nonatomic, assign) MTAudioProcessingTapRef tap;
@property (nonatomic, assign) OCTapContext          *tapContext;
@property (nonatomic, strong) AVAudioFormat         *tapFormat;
@property (nonatomic, strong) AVAudioMix            *audioMix;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, AVMutableAudioMixInputParameters *> *inputParams;

// Smart Speed state
@property (nonatomic, assign) BOOL   smartSpeedCurrentlyBoosting;
@property (nonatomic, assign) CMTime smartSpeedBoostStart;
@property (nonatomic, assign) float  rateBeforeBoost;
@property (nonatomic, assign) BOOL   bypassed;
@end

@implementation OCSkipSilenceEngine

+ (instancetype)shared {
    static OCSkipSilenceEngine *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [OCSkipSilenceEngine new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _settings             = [OCSettings shared];
        _tracker              = [OCSmartSpeedTracker shared];
        _detector             = [[OCSilenceDetector alloc] initWithSampleRate:48000 channels:2];
        _detector.delegate    = self;
        _classifier           = [[OCAudioClassifier alloc] initWithClassifierIdentifier:@"SNClassifierIdentifierVersion1" error:NULL];
        _classifier.delegate  = self;
        _baselineSpeed        = [OCAudioPlaybackSpeed standardSpeed];
        _silenceSkippingSpeed = [OCAudioPlaybackSpeed speedWithRate:2.0];
        _voiceBoostConfiguration = [OCVoiceBoostConfiguration standardConfiguration];
        _inputParams = [NSMutableDictionary dictionary];
        [self reloadSettings];

        // Observe bypass-change notifications from the tracker so we can
        // restore playback rate.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(smartSpeedBypassDidChange:)
                                                     name:OCSmartSpeedBypassDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self detach];
}

#pragma mark - YTLiteExtensionProtocol

- (void)extensionDidActivate {
    OCLogI(General, @"YTLite extension activated");
    [self reloadSettings];
}
- (void)extensionDidDeactivate {
    OCLogI(General, @"YTLite extension deactivated");
    [self detach];
}

#pragma mark - Settings

- (void)reloadSettings {
    OCSettings *s = self.settings;
    self.skipSilences                   = s.skipSilences;
    self.useSmartSpeed                  = s.useSmartSpeed;
    self.useSmartSpeedMusicDetection    = s.useSmartSpeedMusicDetection;
    self.useVoiceBoost                  = s.useVoiceBoost;
    self.standardVoiceBoostConfiguration = s.standardVoiceBoostConfiguration;

    self.detector.silenceThresholdDBFS   = s.silenceThresholdDBFS;
    self.detector.minimumSilenceDuration = s.minimumSilenceDuration;

    self.baselineSpeed        = [OCAudioPlaybackSpeed speedWithRate:s.baselineSpeed];
    self.silenceSkippingSpeed = [OCAudioPlaybackSpeed speedWithRate:s.silenceSkippingSpeed];

    if (s.standardVoiceBoostConfiguration) {
        self.voiceBoostConfiguration = [OCVoiceBoostConfiguration standardConfiguration];
    } else {
        self.voiceBoostConfiguration = [OCVoiceBoostConfiguration
            configurationWithTargetLUFS:s.voiceBoostTargetLUFS
                     compressorThreshold:s.voiceBoostCompressorThreshold
                        deEsserThreshold:s.voiceBoostDeEsserThreshold
                              masterGain:3.0];
    }

    OCLogVerboseEnabled = s.verboseLogging;
    OCLogI(General, @"settings reloaded: skipSilences=%d useSmartSpeed=%d threshold=%.1f dur=%.2f skipRate=%.2f",
           self.skipSilences, self.useSmartSpeed,
           s.silenceThresholdDBFS, s.minimumSilenceDuration, s.silenceSkippingSpeed);
}

#pragma mark - Attach / Detach

- (void)attachToPlayer:(AVPlayer *)player {
    if (!player) return;
    [self detach];
    _player = player;
    _playerItem = player.currentItem;
    if (!_playerItem) {
        OCLogW(Audio, @"attach: player has no currentItem — deferring");
        return;
    }
    [self installAudioTap];
}

- (void)detach {
    if (_tap) {
        // The tap is owned by the audioMix inputParameters. Clearing the mix
        // releases the tap.
        _playerItem.audioMix = nil;
        _tap = NULL;
    }
    if (_tapContext) {
        free(_tapContext);
        _tapContext = NULL;
    }
    _tapFormat = nil;
    _audioMix = nil;
    _inputParams = [NSMutableDictionary dictionary];
    _player = nil;
    _playerItem = nil;
    _smartSpeedCurrentlyBoosting = NO;
    [self.detector reset];
}

- (void)installAudioTap {
    if (!MTAudioProcessingTapCreate) {
        OCLogE(Audio, @"MTAudioProcessingTapCreate unavailable — silence detection disabled");
        return;
    }

    AVAssetTrack *audioTrack = [self audioTrackForItem:_playerItem];
    if (!audioTrack) {
        OCLogW(Audio, @"no audio track found — cannot install tap");
        return;
    }

    // Build the audio format from the track's format description.
    CMAudioFormatDescriptionRef fmtDesc = NULL;
    if (CMTimedAudioFormatDescriptionRef td = (__bridge CMTimedAudioFormatDescriptionRef)[audioTrack.formatDescriptions firstObject]) {
        fmtDesc = (CMAudioFormatDescriptionRef)td;
    }
    AudioStreamBasicDescription asbd = {0};
    if (fmtDesc) {
        const AudioStreamBasicDescription *src = CMAudioFormatDescriptionGetStreamDescription(fmtDesc);
        if (src) asbd = *src;
    }
    if (asbd.mSampleRate == 0) {
        asbd.mSampleRate = 48000;
        asbd.mFormatID   = kAudioFormatLinearPCM;
        asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        asbd.mFramesPerPacket = 1;
        asbd.mChannelsPerFrame = 2;
        asbd.mBitsPerChannel = 32;
        asbd.mBytesPerFrame = 8;
        asbd.mBytesPerPacket = 8;
    }
    _tapFormat = [[AVAudioFormat alloc] initWithStreamDescription:&asbd];

    OCTapContext *c = (OCTapContext *)calloc(1, sizeof(OCTapContext));
    c->engine = self;
    c->asbd   = asbd;
    c->format = _tapFormat;
    _tapContext = c;

    OCTapCallbacks cbs = {0};
    cbs.version   = 0;
    cbs.clientHandle = c;
    cbs.init      = OCTapInit;
    cbs.finalize  = OCTapFinalize;
    cbs.prepare   = OCTapPrepare;
    cbs.unprepare = OCTapUnprepare;
    cbs.process   = OCTapProcess;

    OSStatus err = MTAudioProcessingTapCreate(NULL, &cbs,
                                              kMTAudioProcessingTapCreationFlag_PreEffects,
                                              &_tap);
    if (err != noErr || !_tap) {
        OCLogE(Audio, @"MTAudioProcessingTapCreate failed: %d", (int)err);
        free(c); _tapContext = NULL;
        return;
    }

    AVMutableAudioMixInputParameters *p =
        [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:audioTrack];
    p.audioTapProcessor = (__bridge void *)_tap;
    self.inputParams[@(audioTrack.trackID)] = p;

    AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
    mix.inputParameters = self.inputParams.allValues;
    _audioMix = mix;
    _playerItem.audioMix = mix;

    OCLogI(Audio, @"audio tap installed on track %d (sr=%.0f ch=%u)",
           (int)audioTrack.trackID, asbd.mSampleRate, (unsigned)asbd.mChannelsPerFrame);
}

- (AVAssetTrack *)audioTrackForItem:(AVPlayerItem *)item {
    if (!item || !item.asset) return nil;
    NSArray<AVAssetTrack *> *tracks = [item.asset tracksWithMediaType:AVMediaTypeAudio];
    return tracks.firstObject;
}

#pragma mark - Tap processing (called on the audio render thread)

- (void)_processTapBufferList:(CMAudioBufferList *)bl
                       frames:(UInt32)frames
                         time:(CMTime)time
                       format:(AVAudioFormat *)format {
    if (frames == 0 || !format) return;

    AVAudioPCMBuffer *buf = OCBuildPCMBuffer(bl, frames, format);
    if (!buf) return;

    // Update detector's sample rate if it changed.
    if (fabsf(self.detector.sampleRate - format.sampleRate) > 0.1) {
        self.detector.sampleRate = format.sampleRate;
    }
    if (self.detector.channels != format.channelCount) {
        self.detector.channels = format.channelCount;
    }

    [self.detector processPCMBuffer:buf atTime:time];

    if (self.useSmartSpeed && self.useSmartSpeedMusicDetection) {
        [self.classifier processBuffer:buf atTime:time];
    }
}

#pragma mark - OCSilenceDetectorDelegate

- (void)silenceDetectorDidDetectSilenceStart:(CMTime)startTime avgDBFS:(float)avg {
    if (!self.useSmartSpeed) return;
    if (self.bypassed) {
        OCLogD(SmartSpeed, @"silence start ignored — bypassed");
        return;
    }
    if (self.smartSpeedCurrentlyBoosting) return;
    self.smartSpeedCurrentlyBoosting = YES;
    self.smartSpeedBoostStart = startTime;
    self.rateBeforeBoost = _player.rate;
    float boostRate = self.silenceSkippingSpeed.clampedRate;
    _player.rate = boostRate;
    OCLogI(SmartSpeed, @"smart speed ON: rate %.2f → %.2f at %.3fs",
           self.rateBeforeBoost, boostRate, CMTimeGetSeconds(startTime));
}

- (void)silenceDetectorDidDetectSilenceEnd:(CMTime)endTime avgDBFS:(float)avg
                                   duration:(NSTimeInterval)dur {
    if (!self.useSmartSpeed) {
        // Skip Silences-only mode: if the region is long enough, seek forward.
        if (self.skipSilences && dur >= self.detector.minimumSilenceDuration) {
            CMTime target = CMTimeAdd(endTime, CMTimeMakeWithSeconds(self.detector.lookaheadBuffer, 600));
            [_player seekToTime:target toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero
                  completionHandler:^(BOOL finished) {
                if (finished) {
                    [self.tracker recordSkippedInterval:self.smartSpeedBoostStart
                                                      to:target
                                            baselineRate:self.baselineSpeed.rate];
                }
            }];
            OCLogI(SkipSilence, @"skip silence: seek to %.3fs (saved %.3fs)",
                   CMTimeGetSeconds(target), dur);
        }
        return;
    }
    if (self.bypassed) return;
    if (!self.smartSpeedCurrentlyBoosting) return;
    self.smartSpeedCurrentlyBoosting = NO;
    float restored = self.rateBeforeBoost > 0 ? self.rateBeforeBoost : self.baselineSpeed.clampedRate;
    _player.rate = restored;
    [self.tracker recordSmartSpeedInterval:self.smartSpeedBoostStart
                                        to:endTime
                              baselineRate:self.baselineSpeed.rate
                           silenceSkipRate:self.silenceSkippingSpeed.rate];
    OCLogI(SmartSpeed, @"smart speed OFF: rate → %.2f at %.3fs (saved ~%.3fs)",
           restored, CMTimeGetSeconds(endTime), dur * (self.silenceSkippingSpeed.rate / self.baselineSpeed.rate - 1));
}

#pragma mark - OCAudioClassifierDelegate

- (void)audioClassifier:(OCAudioClassifier *)classifier
       didProduceResult:(OCAudioClassifierResult *)result {
    if (!self.useSmartSpeedMusicDetection) {
        [self.tracker setBypassed:NO reason:@"music detection disabled"];
        return;
    }
    if (result.label == OCAudioClassifierLabelMusic && result.confidence > 0.6) {
        [self.tracker setBypassed:YES reason:@"music detected"];
    } else if (result.label == OCAudioClassifierLabelSpeech && result.confidence > 0.6) {
        [self.tracker setBypassed:NO reason:@"speech detected"];
    }
}

#pragma mark - Bypass changes

- (void)smartSpeedBypassDidChange:(NSNotification *)n {
    BOOL bypassed = [n.userInfo[@"bypassed"] boolValue];
    self.bypassed = bypassed;
    if (bypassed && self.smartSpeedCurrentlyBoosting) {
        // Restore the rate immediately — we're entering a music section.
        float restored = self.rateBeforeBoost > 0 ? self.rateBeforeBoost : self.baselineSpeed.clampedRate;
        _player.rate = restored;
        self.smartSpeedCurrentlyBoosting = NO;
        OCLogI(SmartSpeed, @"bypass mid-silence: rate → %.2f", restored);
    }
}

#pragma mark - Overcast-mirrored selectors

- (BOOL)seekToNextSilenceWithMinimumSampleDuration:(NSTimeInterval)minDuration
                                         threshold:(float)thresholdDBFS {
    NSTimeInterval now = CMTimeGetSeconds(_player.currentTime);
    NSTimeInterval horizon = now + 60.0; // look up to a minute ahead
    CMTime target = [self timestampOfNearestSilenceBetweenStartTime:_player.currentTime
                                                              endTime:CMTimeMakeWithSeconds(horizon, 600)
                                                      silenceThreshold:thresholdDBFS];
    if (CMTIME_IS_INVALID(target)) return NO;
    [_player seekToTime:target toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    return YES;
}

- (nullable CMTime)timestampOfNearestSilenceBetweenStartTime:(CMTime)startTime
                                                      endTime:(CMTime)endTime
                                              silenceThreshold:(float)thresholdDBFS {
    float oldThreshold = self.detector.silenceThresholdDBFS;
    self.detector.silenceThresholdDBFS = thresholdDBFS;
    OCSilenceRegion *r = [self.detector findNearestSilenceInRegions:self.detector.recentRegions
                                                          fromTime:startTime
                                                            toTime:endTime];
    self.detector.silenceThresholdDBFS = oldThreshold;
    if (!r) return kCMTimeInvalid;
    return r.startTime;
}

- (BOOL)seekToNearestSilenceBetweenStartTime:(CMTime)startTime endTime:(CMTime)endTime {
    CMTime t = [self timestampOfNearestSilenceBetweenStartTime:startTime
                                                        endTime:endTime
                                                silenceThreshold:self.detector.silenceThresholdDBFS];
    if (CMTIME_IS_INVALID(t)) return NO;
    [_player seekToTime:t toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    return YES;
}

- (BOOL)seekToNearestSilenceBetweenStartTime:(CMTime)startTime
                                      endTime:(CMTime)endTime
                                     thenPlay:(BOOL)play {
    BOOL ok = [self seekToNearestSilenceBetweenStartTime:startTime endTime:endTime];
    if (ok && play && _player.rate == 0) {
        [_player play];
    }
    return ok;
}

- (BOOL)seekByInterval:(NSTimeInterval)interval findNearestSilence:(BOOL)nearest {
    CMTime now = _player.currentTime;
    CMTime target = CMTimeAdd(now, CMTimeMakeWithSeconds(interval, 600));
    if (nearest) {
        CMTime end = CMTimeAdd(target, CMTimeMakeWithSeconds(2.0, 600));
        return [self seekToNearestSilenceBetweenStartTime:target endTime:end];
    }
    [_player seekToTime:target toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    return YES;
}

#pragma mark - Read-only mirrors

- (BOOL)isSmartSpeedBypassed { return self.tracker.isSmartSpeedBypassed; }
- (const int64_t *)timelineSilenceSkippedSamples { return self.tracker.timelineSilenceSkippedSamples; }
- (NSUInteger)timelineSilenceSkippedSamplesCount { return self.tracker.timelineSilenceSkippedSamplesCount; }
- (NSTimeInterval)smartSpeedTotalSavings { return self.tracker.smartSpeedTotalSavings; }
- (NSTimeInterval)smartSpeedSavingsSinceLastSync { return self.tracker.smartSpeedSavingsSinceLastSync; }

@end
