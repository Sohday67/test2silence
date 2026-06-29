//
//  OCAudioPlaybackSpeed.m
//  YTLiteSkipSilence
//

#import "OCAudioPlaybackSpeed.h"

static const float kOCSpeedMin = 0.25f;
static const float kOCSpeedMax = 3.0f;

@implementation OCAudioPlaybackSpeed

+ (instancetype)standardSpeed {
    return [[self alloc] initWithRate:1.0f];
}

+ (instancetype)speedWithRate:(float)rate {
    return [[self alloc] initWithRate:rate];
}

// Override NSObject's designated initializer to delegate to ours.
- (instancetype)init {
    return [self initWithRate:1.0f];
}

- (instancetype)initWithRate:(float)rate {
    if ((self = [super init])) {
        _rate = rate;
    }
    return self;
}

- (float)clampedRate {
    if (_rate < kOCSpeedMin) return kOCSpeedMin;
    if (_rate > kOCSpeedMax) return kOCSpeedMax;
    return _rate;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] initWithRate:_rate];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeFloat:_rate forKey:@"rate"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    float r = [coder decodeFloatForKey:@"rate"];
    return [self initWithRate:r];
}

#pragma mark - NSObject

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[OCAudioPlaybackSpeed class]]) return NO;
    return fabsf(((OCAudioPlaybackSpeed *)object).rate - _rate) < 0.0001f;
}

- (NSUInteger)hash { return @( _rate ).hash; }

- (NSString *)description {
    return [NSString stringWithFormat:@"<OCAudioPlaybackSpeed rate=%.3f>", _rate];
}

@end
