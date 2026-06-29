//
//  OCAudioClassifier.h
//  YTLiteSkipSilence
//
//  Faithful Objective-C port of Overcast's `OCAudioClassifier` (Swift symbol
//  `_TtC7OCAudio17OCAudioClassifier`). Overcast uses this class to perform
//  speech / music discrimination via Apple's SoundAnalysis framework
//  (SNClassifierIdentifierVersion1), which powers the
//  `useSmartSpeedMusicDetection` Smart Speed switch: when music is detected,
//  Smart Speed is bypassed so songs play at their natural rate.
//
//  We expose the same identifier-based initializer that Overcast uses
//  (`initWithClassifierIdentifier:error:`) plus a delegate protocol mirroring
//  SNResultsObserving.
//

#ifndef OCAudioClassifier_h
#define OCAudioClassifier_h

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OCAudioClassifierLabel) {
    OCAudioClassifierLabelUnknown   = 0,
    OCAudioClassifierLabelSpeech    = 1,
    OCAudioClassifierLabelMusic     = 2,
    OCAudioClassifierLabelSilence   = 3,
};

@interface OCAudioClassifierResult : NSObject
@property (nonatomic, assign) OCAudioClassifierLabel label;
@property (nonatomic, assign) float confidence;
@property (nonatomic, assign) CMTime startTime;
@property (nonatomic, assign) CMTime endTime;
+ (instancetype)resultWithLabel:(OCAudioClassifierLabel)label
                     confidence:(float)confidence
                      startTime:(CMTime)s
                        endTime:(CMTime)e;
@end

@protocol OCAudioClassifierDelegate <NSObject>
@optional
- (void)audioClassifier:(id)classifier didProduceResult:(OCAudioClassifierResult *)result;
@end

@interface OCAudioClassifier : NSObject

// Mirrors Overcast's -[OCAudioClassifier initWithClassifierIdentifier:error:].
// `identifier` is the SoundAnalysis classifier identifier string
// (SNClassifierIdentifierVersion1).
- (nullable instancetype)initWithClassifierIdentifier:(NSString *)identifier
                                                error:(NSError **)error
                                              NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, weak) id<OCAudioClassifierDelegate> delegate;

// Push a buffer for classification (called from the same audio tap as
// the silence detector).
- (void)processBuffer:(AVAudioPCMBuffer *)buffer atTime:(CMTime)time;

// Convenience — return the most-recent label for an immediate decision.
@property (nonatomic, readonly) OCAudioClassifierLabel currentLabel;
@property (nonatomic, readonly) float                  currentConfidence;

// Reset.
- (void)reset;

@end

NS_ASSUME_NONNULL_END

#endif /* OCAudioClassifier_h */
