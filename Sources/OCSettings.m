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
@property (nonatomic, readwrite, strong) NSUserDefaults *defaults;
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
        OCLogVerboseEnabled = self.verboseLogging;
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

#pragma mark - BOOL properties

- (BOOL)enabled { return [_defaults boolForKey:OCSettingsKeyEnabled]; }
- (void)setEnabled:(BOOL)v { [_defaults setBool:v forKey:OCSettingsKeyEnabled]; }

- (BOOL)skipSilences { return [_defaults boolForKey:OCSettingsKeySkipSilences]; }
- (void)setSkipSilences:(BOOL)v { [_defaults setBool:v forKey:OCSettingsKeySkipSilences]; }

- (BOOL)useSmartSpeed { return [_defaults boolForKey:OCSettingsKeyUseSmartSpeed]; }
- (void)setUseSmartSpeed:(BOOL)v { [_defaults setBool:v forKey:OCSettingsKeyUseSmartSpeed]; }

- (BOOL)useSmartSpeedMusicDetection { return [_defaults boolForKey:OCSettingsKeyUseSmartSpeedMusicDetection]; }
- (void)setUseSmartSpeedMusicDetection:(BOOL)v { [_defaults setBool:v forKey:OCSettingsKeyUseSmartSpeedMusicDetection]; }

- (BOOL)useVoiceBoost { return [_defaults boolForKey:OCSettingsKeyUseVoiceBoost]; }
- (void)setUseVoiceBoost:(BOOL)v { [_defaults setBool:v forKey:OCSettingsKeyUseVoiceBoost]; }

- (BOOL)standardVoiceBoostConfiguration { return [_defaults boolForKey:OCSettingsKeyStandardVoiceBoostConfiguration]; }
- (void)setStandardVoiceBoostConfiguration:(BOOL)v { [_defaults setBool:v forKey:OCSettingsKeyStandardVoiceBoostConfiguration]; }

- (BOOL)showTimeSavedHUD { return [_defaults boolForKey:OCSettingsKeyShowTimeSavedHUD]; }
- (void)setShowTimeSavedHUD:(BOOL)v { [_defaults setBool:v forKey:OCSettingsKeyShowTimeSavedHUD]; }

- (BOOL)verboseLogging { return [_defaults boolForKey:OCSettingsKeyVerboseLogging]; }
- (void)setVerboseLogging:(BOOL)v {
    [_defaults setBool:v forKey:OCSettingsKeyVerboseLogging];
    OCLogVerboseEnabled = v;
}

#pragma mark - float properties

- (float)silenceThresholdDBFS { return [_defaults floatForKey:OCSettingsKeySilenceThresholdDBFS]; }
- (void)setSilenceThresholdDBFS:(float)v { [_defaults setFloat:v forKey:OCSettingsKeySilenceThresholdDBFS]; }

- (float)silenceSkippingSpeed { return [_defaults floatForKey:OCSettingsKeySilenceSkippingSpeed]; }
- (void)setSilenceSkippingSpeed:(float)v { [_defaults setFloat:v forKey:OCSettingsKeySilenceSkippingSpeed]; }

- (float)baselineSpeed { return [_defaults floatForKey:OCSettingsKeyBaselineSpeed]; }
- (void)setBaselineSpeed:(float)v { [_defaults setFloat:v forKey:OCSettingsKeyBaselineSpeed]; }

- (float)voiceBoostCompressorThreshold { return [_defaults floatForKey:OCSettingsKeyVoiceBoostCompressorThreshold]; }
- (void)setVoiceBoostCompressorThreshold:(float)v { [_defaults setFloat:v forKey:OCSettingsKeyVoiceBoostCompressorThreshold]; }

- (float)voiceBoostDeEsserThreshold { return [_defaults floatForKey:OCSettingsKeyVoiceBoostDeEsserThreshold]; }
- (void)setVoiceBoostDeEsserThreshold:(float)v { [_defaults setFloat:v forKey:OCSettingsKeyVoiceBoostDeEsserThreshold]; }

#pragma mark - NSTimeInterval properties

- (NSTimeInterval)minimumSilenceDuration { return [_defaults doubleForKey:OCSettingsKeyMinimumSilenceDuration]; }
- (void)setMinimumSilenceDuration:(NSTimeInterval)v { [_defaults setDouble:v forKey:OCSettingsKeyMinimumSilenceDuration]; }

- (NSTimeInterval)smartSpeedTotalSavings { return [_defaults doubleForKey:OCSettingsKeySmartSpeedTotalSavings]; }
- (void)setSmartSpeedTotalSavings:(NSTimeInterval)v { [_defaults setDouble:v forKey:OCSettingsKeySmartSpeedTotalSavings]; }

- (NSTimeInterval)smartSpeedSavingsSinceLastSync { return [_defaults doubleForKey:OCSettingsKeySmartSpeedSavingsSinceLastSync]; }
- (void)setSmartSpeedSavingsSinceLastSync:(NSTimeInterval)v { [_defaults setDouble:v forKey:OCSettingsKeySmartSpeedSavingsSinceLastSync]; }

#pragma mark - NSInteger properties

- (NSInteger)voiceBoostTargetLUFS { return [_defaults integerForKey:OCSettingsKeyVoiceBoostTargetLUFS]; }
- (void)setVoiceBoostTargetLUFS:(NSInteger)v { [_defaults setInteger:v forKey:OCSettingsKeyVoiceBoostTargetLUFS]; }

#pragma mark - Convenience

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
