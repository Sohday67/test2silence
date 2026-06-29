//
//  OCAudioClassifier.m
//  YTLiteSkipSilence
//
//  Implementation uses Apple's SoundAnalysis framework (SNClassifierIdentifierVersion1),
//  the same classifier identifier Overcast uses internally.
//

#import "OCAudioClassifier.h"
#import "OCLog.h"
#import <SoundAnalysis/SoundAnalysis.h>
#import <AVFAudio/AVFAudio.h>

@interface OCAudioClassifierResult ()
@property (nonatomic, assign) OCAudioClassifierLabel label;
@property (nonatomic, assign) float confidence;
@property (nonatomic, assign) CMTime startTime;
@property (nonatomic, assign) CMTime endTime;
@end

@implementation OCAudioClassifierResult
+ (instancetype)resultWithLabel:(OCAudioClassifierLabel)label
                     confidence:(float)confidence
                      startTime:(CMTime)s
                        endTime:(CMTime)e {
    OCAudioClassifierResult *r = [OCAudioClassifierResult new];
    r.label = label;
    r.confidence = confidence;
    r.startTime = s;
    r.endTime = e;
    return r;
}
- (NSString *)description {
    return [NSString stringWithFormat:@"<ClassifierResult label=%ld conf=%.2f [%.3f→%.3f]>",
        (long)self.label, self.confidence, CMTimeGetSeconds(self.startTime), CMTimeGetSeconds(self.endTime)];
}
@end

// SNResultsObserving bridge — SoundAnalysis requires a class that conforms to
// the protocol. We cannot use the Logos-compiled class directly because
// SNResultsObserving is a Swift protocol; we use NSObject + objc bridging.
@interface OCClassifierResultObserver : NSObject <SNResultsObserving>
@property (nonatomic, weak) OCAudioClassifier *owner;
@end

@implementation OCClassifierResultObserver
- (void)request:(id<SNRequest>)request didProduceResult:(id<SNResult>)result {
    if ([result isKindOfClass:[SNClassificationResult class]]) {
        SNClassificationResult *cr = (SNClassificationResult *)result;
        SNClassification *best = nil;
        for (SNClassification *c in cr.classifications) {
            if (!best || c.confidence > best.confidence) best = c;
        }
        if (!best) return;

        OCAudioClassifierLabel label = OCAudioClassifierLabelUnknown;
        NSString *id_ = best.identifier.lowercaseString;
        if ([id_ containsString:@"speech"] || [id_ containsString:@"voice"] || [id_ containsString:@"talk"]) {
            label = OCAudioClassifierLabelSpeech;
        } else if ([id_ containsString:@"music"]) {
            label = OCAudioClassifierLabelMusic;
        } else if ([id_ containsString:@"silence"]) {
            label = OCAudioClassifierLabelSilence;
        }

        OCAudioClassifierResult *res = [OCAudioClassifierResult
            resultWithLabel:label
                 confidence:best.confidence
                  startTime:cr.timeRange.start
                    endTime:CMTimeAdd(cr.timeRange.start, cr.timeRange.duration)];

        OCAudioClassifier *o = self.owner;
        if (o && [o.delegate respondsToSelector:@selector(audioClassifier:didProduceResult:)]) {
            [o.delegate audioClassifier:o didProduceResult:res];
        }
        [o setValue:@(label)    forKey:@"currentLabelInternal"];
        [o setValue:@(best.confidence) forKey:@"currentConfidenceInternal"];
    }
}
@end

@interface OCAudioClassifier ()
@property (nonatomic, strong) SNClassifySoundRequest   *request;
@property (nonatomic, strong) SNAudioStreamAnalyzer    *analyzer;
@property (nonatomic, strong) OCClassifierResultObserver *observer;
@property (nonatomic, strong) dispatch_queue_t          queue;
@property (nonatomic, strong) AVAudioFormat            *format;
@property (nonatomic, assign) OCAudioClassifierLabel   currentLabel;
@property (nonatomic, assign) float                    currentConfidence;
@end

@implementation OCAudioClassifier

- (nullable instancetype)initWithClassifierIdentifier:(NSString *)identifier
                                                error:(NSError **)error {
    if ((self = [super init])) {
        _currentLabel = OCAudioClassifierLabelUnknown;
        _currentConfidence = 0;
        _queue = dispatch_queue_create("com.ytlite.skipsilence.classifier", DISPATCH_QUEUE_SERIAL);

        _analyzer = [[SNAudioStreamAnalyzer alloc] initWithFormat:[[AVAudioFormat alloc]
                            initWithCommonFormat:AVAudioPCMFormatFloat32
                                      sampleRate:48000
                                        channels:2
                                  interleaved:NO]];
        _request = [[SNClassifySoundRequest alloc] initWithClassifierIdentifier:identifier];
        _observer = [OCClassifierResultObserver new];
        _observer.owner = self;

        NSError *e = nil;
        BOOL ok = [_analyzer add:_request withObserver:_observer error:&e];
        if (!ok) {
            if (error) *error = e ?: [NSError errorWithDomain:@"OCAudioClassifier" code:1
                                                       userInfo:@{NSLocalizedDescriptionKey: @"add request failed"}];
            OCLogW(Classifier, @"failed to add classify request: %@", e);
            return nil;
        }
        OCLogI(Classifier, @"classifier initialized with identifier=%@", identifier);
    }
    return self;
}

- (void)processBuffer:(AVAudioPCMBuffer *)buffer atTime:(CMTime)time {
    if (!buffer || !buffer.format) return;
    // Re-create analyzer if sample rate changed.
    if (!_format || _format.sampleRate != buffer.format.sampleRate
                 || _format.channelCount != buffer.format.channelCount) {
        _format = buffer.format;
        _analyzer = [[SNAudioStreamAnalyzer alloc] initWithFormat:_format];
        NSError *e = nil;
        if (![_analyzer add:_request withObserver:_observer error:&e]) {
            OCLogW(Classifier, @"re-add classify request failed: %@", e);
        }
    }
    [_analyzer analyzeAudioBuffer:buffer atAudioFramePosition:CMTimeGetSeconds(time) * (double)_format.sampleRate];
}

- (void)reset {
    _currentLabel = OCAudioClassifierLabelUnknown;
    _currentConfidence = 0;
}

@end
