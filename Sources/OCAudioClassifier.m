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

// ----------------------------------------------------------------------------
//  Forward declaration of the observer class so the class extension below
//  can use it as a property type. The full @interface follows further down.
// ----------------------------------------------------------------------------
@class OCClassifierResultObserver;

// ----------------------------------------------------------------------------
//  Class extension — must come before the observer class implementation so
//  the observer can see the readwrite setters for currentLabel and
//  currentConfidence.
// ----------------------------------------------------------------------------
@interface OCAudioClassifier ()
@property (nonatomic, strong) SNClassifySoundRequest             *request;
@property (nonatomic, strong) SNAudioStreamAnalyzer              *analyzer;
@property (nonatomic, strong) OCClassifierResultObserver         *observer;
@property (nonatomic, strong) dispatch_queue_t                    queue;
@property (nonatomic, strong) AVAudioFormat                      *format;
// Redeclare as readwrite so the result observer can update them.
@property (nonatomic, readwrite, assign) OCAudioClassifierLabel currentLabel;
@property (nonatomic, readwrite, assign) float                  currentConfidence;
@end

// ----------------------------------------------------------------------------
//  SNResultsObserving bridge — SoundAnalysis requires a class that conforms
//  to the SNResultsObserving protocol. We declare the protocol conformance
//  on a plain NSObject subclass here. Forward-declared above so the
//  @property in the class extension can use it.
// ----------------------------------------------------------------------------

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

@interface OCClassifierResultObserver : NSObject <SNResultsObserving>
@property (nonatomic, weak) OCAudioClassifier *owner;
@end

@implementation OCClassifierResultObserver

- (void)request:(id<SNRequest>)request didProduceResult:(id<SNResult>)result {
    if (![result isKindOfClass:[SNClassificationResult class]]) return;
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
             confidence:(float)best.confidence
              startTime:cr.timeRange.start
                endTime:CMTimeAdd(cr.timeRange.start, cr.timeRange.duration)];

    OCAudioClassifier *o = self.owner;
    if (!o) return;
    [o setCurrentLabel:label];
    [o setCurrentConfidence:(float)best.confidence];

    if ([o.delegate respondsToSelector:@selector(audioClassifier:didProduceResult:)]) {
        [o.delegate audioClassifier:o didProduceResult:res];
    }
}

@end

@implementation OCAudioClassifier

- (nullable instancetype)initWithClassifierIdentifier:(NSString *)identifier
                                                error:(NSError **)error {
    if ((self = [super init])) {
        _currentLabel = OCAudioClassifierLabelUnknown;
        _currentConfidence = 0;
        _queue = dispatch_queue_create("com.ytlite.skipsilence.classifier", DISPATCH_QUEUE_SERIAL);

        _observer = [OCClassifierResultObserver new];
        _observer.owner = self;

        // SNClassifierIdentifierVersion1 is the version-1 sounds classifier
        // that Overcast uses. It is available iOS 15+.
        SNClassifierIdentifier snIdentifier = SNClassifierIdentifierVersion1;
        if (![identifier isEqualToString:@"SNClassifierIdentifierVersion1"]) {
            // Treat the identifier string itself as an SNClassifierIdentifier.
            snIdentifier = (SNClassifierIdentifier)identifier;
        }

        NSError *requestErr = nil;
        _request = [[SNClassifySoundRequest alloc] initWithClassifierIdentifier:snIdentifier
                                                                          error:&requestErr];
        if (!_request) {
            if (error) *error = requestErr ?: [NSError errorWithDomain:@"OCAudioClassifier" code:2
                                                                userInfo:@{NSLocalizedDescriptionKey: @"SNClassifySoundRequest init failed"}];
            OCLogW(Classifier, @"failed to init classify request: %@", requestErr);
            return nil;
        }

        AVAudioFormat *fmt = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                              sampleRate:48000
                                                                channels:2
                                                            interleaved:NO];
        _analyzer = [[SNAudioStreamAnalyzer alloc] initWithFormat:fmt];

        NSError *e = nil;
        BOOL ok = [_analyzer addRequest:_request withObserver:_observer error:&e];
        if (!ok) {
            if (error) *error = e ?: [NSError errorWithDomain:@"OCAudioClassifier" code:1
                                                       userInfo:@{NSLocalizedDescriptionKey: @"addRequest failed"}];
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
        if (![_analyzer addRequest:_request withObserver:_observer error:&e]) {
            OCLogW(Classifier, @"re-add classify request failed: %@", e);
        }
    }
    AVAudioFramePosition pos = (AVAudioFramePosition)(CMTimeGetSeconds(time) * (double)_format.sampleRate);
    [_analyzer analyzeAudioBuffer:buffer atAudioFramePosition:pos];
}

- (void)reset {
    _currentLabel = OCAudioClassifierLabelUnknown;
    _currentConfidence = 0;
}

@end
