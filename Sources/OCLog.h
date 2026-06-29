//
//  OCLog.h
//  YTLiteSkipSilence
//
//  Lightweight logging shim that mirrors Overcast's os_log-style logging.
//  Uses os_log directly when available; falls back to NSLog.
//

#ifndef OCLog_h
#define OCLog_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Log categories — kept in sync with Overcast's subsystem categories
// (com.marcoarment.overcast.audio, .smartspeed, .voiceboost)
typedef NS_ENUM(NSInteger, OCLogCategory) {
    OCLogCategoryGeneral     = 0,
    OCLogCategoryAudio       = 1,
    OCLogCategorySmartSpeed  = 2,
    OCLogCategoryVoiceBoost  = 3,
    OCLogCategorySkipSilence = 4,
    OCLogCategoryClassifier  = 5,
};

void OCLogDebug(OCLogCategory cat, NSString *fmt, ...) NS_FORMAT_FUNCTION(2, 3);
void OCLogInfo(OCLogCategory cat, NSString *fmt, ...)  NS_FORMAT_FUNCTION(2, 3);
void OCLogWarn(OCLogCategory cat, NSString *fmt, ...)  NS_FORMAT_FUNCTION(2, 3);
void OCLogError(OCLogCategory cat, NSString *fmt, ...) NS_FORMAT_FUNCTION(2, 3);

// Compact macros
#define OCLogD(cat, ...) OCLogDebug(OCLogCategory##cat, __VA_ARGS__)
#define OCLogI(cat, ...) OCLogInfo (OCLogCategory##cat, __VA_ARGS__)
#define OCLogW(cat, ...) OCLogWarn (OCLogCategory##cat, __VA_ARGS__)
#define OCLogE(cat, ...) OCLogError(OCLogCategory##cat, __VA_ARGS__)

// Convenience — verbose logging toggle
extern BOOL OCLogVerboseEnabled;

#ifdef __cplusplus
}
#endif

#endif /* OCLog_h */
