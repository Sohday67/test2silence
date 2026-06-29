//
//  OCSettings.m
//  YTLiteSkipSilence
//

#import "OCSettings.h"
#import "OCLog.h"

// Same defaults Overcast ships with.
static const float     kOCDefaultSilenceThresholdDBFS        = -40.0f;
static const NSTimeInterval kOCDefaultMinimumSilenceDuration = 0.5;
static const float     kOCDefaultSilenceSkippingSpeed        = 2.0f;
static const float     kOCDefaultBaselineSpeed               = 1.0f;
static const NSInteger kOCDefaultVoiceBoostTargetLUFS        = -16;
static const float     kOCDefaultVoiceBoostCompressor        = -24.0f;
static const float     kOCDefaultVoiceBoostDeEsser           = -30.0f;

NSString * const OCSettingsKeyEnabled                              = @"OCSSEnabled";
NSString * const OCSettingsKeySkipSilences                         = @"OCSSSkipSilences";
NSString * const OCSettingsKeyUseSmartSpeed                        = @"OCSSUseSmartSpeed";
NSString * const OCSettingsKeyUseSmartSpeedMusicDetection          = @"OCSSUseSmartSpeedMusicDetection";
NSString * const OCSettingsKeyUseVoiceBoost                        = @"OCSSUseVoiceBoost";
NSString * const OCSettingsKeyStandardVoiceBoostConfiguration      = @"OCSSStandardVoiceBoostConfiguration";
NSString * const OCSettingsKeySilenceThresholdDBFS                 = @"OCSSSilenceThresholdDBFS";
NSString * const OCSettingsKeyMinimumSilenceDuration               = @"OCSSMinimumSilenceDuration";
NSString * const OCSettingsKeySilenceSkippingSpeed                 = @"OCSSSilenceSkippingSpeed";
NSString * const OCSettingsKeyBaselineSpeed                        = @"OCSSBaselineSpeed";
NSString * const OCSettingsKeyVoiceBoostTargetLUFS                 = @"OCSSVoiceBoostTargetLUFS";
NSString * const OCSettingsKeyVoiceBoostCompressorThreshold        = @"OCSSVoiceBoostCompressorThreshold";
NSString * const OCSettingsKeyVoiceBoostDeEsserThreshold           = @"OCSSVoiceBoostDeEsserThreshold";
NSString * const OCSettingsKeySmartSpeedTotalSavings               = @"OCSSSmartSpeedTotalSavings";
NSString * const OCSettingsKeySmartSpeedSavingsSinceLastSync       = @"OCSSSmartSpeedSavingsSinceLastSync";
NSString * const OCSettingsKeyShowTimeSavedHUD                     = @"OCSSShowTimeSavedHUD";
NSString * const OCSettingsKeyVerboseLogging                       = @"OCSSVerboseLogging";

@interface OCSettings ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@end

@implementation OCSettings

+ (instancetype)shared {
    static OCSettings *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [OCSettings new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        // Use a separate suite so we don't pollute YouTube's standard defaults,
        // while staying readable from the settings tweak.
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.ytlite.skipsilence"];
        [self registerDefaults];
        OCLogVerboseEnabled = [self.verboseLogging boolValue] ? YES : NO;
    }
    return self;
}

- (void)registerDefaults {
    NSDictionary *d = @{
        OCSettingsKeyEnabled:                              @YES,
        OCSettingsKeySkipSilences:                         @YES,
        OCSettingsKeyUseSmartSpeed:                        @NO,
        OCSettingsKeyUseSmartSpeedMusicDetection:          @YES,
        OCSettingsKeyUseVoiceBoost:                        @NO,
        OCSettingsKeyStandardVoiceBoostConfiguration:      @YES,
        OCSettingsKeySilenceThresholdDBFS:                 @(kOCDefaultSilenceThresholdDBFS),
        OCSettingsKeyMinimumSilenceDuration:               @(kOCDefaultMinimumSilenceDuration),
        OCSettingsKeySilenceSkippingSpeed:                 @(kOCDefaultSilenceSkippingSpeed),
        OCSettingsKeyBaselineSpeed:                        @(kOCDefaultBaselineSpeed),
        OCSettingsKeyVoiceBoostTargetLUFS:                 @(kOCDefaultVoiceBoostTargetLUFS),
        OCSettingsKeyVoiceBoostCompressorThreshold:        @(kOCDefaultVoiceBoostCompressor),
        OCSettingsKeyVoiceBoostDeEsserThreshold:           @(kOCDefaultVoiceBoostDeEsser),
        OCSettingsKeySmartSpeedTotalSavings:               @0.0,
        OCSettingsKeySmartSpeedSavingsSinceLastSync:       @0.0,
        OCSettingsKeyShowTimeSavedHUD:                     @YES,
        OCSettingsKeyVerboseLogging:                       @NO,
    };
    [_defaults registerDefaults:d];
}

#define PROP_GETSET(name, key, type, getter) \
    - (type)name { return [_defaults getter]; } \
    - (void)set##name:(type)v { [_defaults set##name:v forKey:key]; }

PROP_GETSET(enabled,                          OCSettingsKeyEnabled,                          BOOL,           boolForKey:)
PROP_GETSET(skipSilences,                     OCSettingsKeySkipSilences,                     BOOL,           boolForKey:)
PROP_GETSET(useSmartSpeed,                    OCSettingsKeyUseSmartSpeed,                    BOOL,           boolForKey:)
PROP_GETSET(useSmartSpeedMusicDetection,      OCSettingsKeyUseSmartSpeedMusicDetection,      BOOL,           boolForKey:)
PROP_GETSET(useVoiceBoost,                    OCSettingsKeyUseVoiceBoost,                    BOOL,           boolForKey:)
PROP_GETSET(standardVoiceBoostConfiguration,  OCSettingsKeyStandardVoiceBoostConfiguration,  BOOL,           boolForKey:)
PROP_GETSET(showTimeSavedHUD,                 OCSettingsKeyShowTimeSavedHUD,                 BOOL,           boolForKey:)
PROP_GETSET(verboseLogging,                   OCSettingsKeyVerboseLogging,                   BOOL,           boolForKey:)
PROP_GETSET(silenceThresholdDBFS,             OCSettingsKeySilenceThresholdDBFS,             float,          floatForKey:)
PROP_GETSET(minimumSilenceDuration,           OCSettingsKeyMinimumSilenceDuration,           NSTimeInterval, doubleForKey:)
PROP_GETSET(silenceSkippingSpeed,             OCSettingsKeySilenceSkippingSpeed,             float,          floatForKey:)
PROP_GETSET(baselineSpeed,                    OCSettingsKeyBaselineSpeed,                    float,          floatForKey:)
PROP_GETSET(voiceBoostCompressorThreshold,    OCSettingsKeyVoiceBoostCompressorThreshold,    float,          floatForKey:)
PROP_GETSET(voiceBoostDeEsserThreshold,       OCSettingsKeyVoiceBoostDeEsserThreshold,       float,          floatForKey:)
PROP_GETSET(voiceBoostTargetLUFS,             OCSettingsKeyVoiceBoostTargetLUFS,             NSInteger,      integerForKey:)

- (NSTimeInterval)smartSpeedTotalSavings {
    return [_defaults doubleForKey:OCSettingsKeySmartSpeedTotalSavings];
}
- (void)setSmartSpeedTotalSavings:(NSTimeInterval)v {
    [_defaults setDouble:v forKey:OCSettingsKeySmartSpeedTotalSavings];
}

- (NSTimeInterval)smartSpeedSavingsSinceLastSync {
    return [_defaults doubleForKey:OCSettingsKeySmartSpeedSavingsSinceLastSync];
}
- (void)setSmartSpeedSavingsSinceLastSync:(NSTimeInterval)v {
    [_defaults setDouble:v forKey:OCSettingsKeySmartSpeedSavingsSinceLastSync];
}

- (BOOL)isFeatureActive {
    return self.enabled && (self.skipSilences || self.useSmartSpeed);
}

- (void)resetSmartSpeedSavings {
    [self setSmartSpeedTotalSavings:0.0];
    [self setSmartSpeedSavingsSinceLastSync:0.0];
    [self synchronize];
    OCLogI(SmartSpeed, @"reset SmartSpeed savings");
}

- (void)synchronize {
    [_defaults synchronize];
}

@end
