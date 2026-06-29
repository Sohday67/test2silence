//
//  OCLog.m
//  YTLiteSkipSilence
//

#import "OCLog.h"
#import <os/log.h>

BOOL OCLogVerboseEnabled = NO;

static inline os_log_type_t OCLogLevelToOSLogType(int level) {
    switch (level) {
        case 0: return OS_LOG_TYPE_DEBUG;
        case 1: return OS_LOG_TYPE_INFO;
        case 2: return OS_LOG_TYPE_DEFAULT;   // warn
        case 3: return OS_LOG_TYPE_ERROR;
        default: return OS_LOG_TYPE_DEFAULT;
    }
}

static inline const char *OCLogCategoryName(OCLogCategory cat) {
    switch (cat) {
        case OCLogCategoryAudio:       return "audio";
        case OCLogCategorySmartSpeed:  return "smartspeed";
        case OCLogCategoryVoiceBoost:  return "voiceboost";
        case OCLogCategorySkipSilence: return "skipsilence";
        case OCLogCategoryClassifier:  return "classifier";
        case OCLogCategoryGeneral:
        default:                        return "general";
    }
}

static inline os_log_t OCLogCategoryHandle(OCLogCategory cat) {
    static os_log_t handles[6] = {0};
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handles[OCLogCategoryGeneral]     = os_log_create("com.ytlite.skipsilence", "general");
        handles[OCLogCategoryAudio]       = os_log_create("com.ytlite.skipsilence", "audio");
        handles[OCLogCategorySmartSpeed]  = os_log_create("com.ytlite.skipsilence", "smartspeed");
        handles[OCLogCategoryVoiceBoost]  = os_log_create("com.ytlite.skipsilence", "voiceboost");
        handles[OCLogCategorySkipSilence] = os_log_create("com.ytlite.skipsilence", "skipsilence");
        handles[OCLogCategoryClassifier]  = os_log_create("com.ytlite.skipsilence", "classifier");
    });
    return handles[cat];
}

static void OCLogV(OCLogCategory cat, int level, NSString *fmt, va_list args) {
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:args];
    const char *cname = OCLogCategoryName(cat);
    os_log_type_t t = OCLogLevelToOSLogType(level);
    os_log_t h = OCLogCategoryHandle(cat);
    os_log_with_type(h, t, "%{public}s: %{public}s", cname, [body UTF8String]);

    // Mirror to stderr when verbose so users can see it in a console capture.
    if (OCLogVerboseEnabled && (level >= 1 || t == OS_LOG_TYPE_ERROR)) {
        fprintf(stderr, "[YTLiteSkipSilence/%s] %s\n", cname, [body UTF8String]);
    }
}

void OCLogDebug(OCLogCategory cat, NSString *fmt, ...) {
    if (!OCLogVerboseEnabled) return;
    va_list a; va_start(a, fmt);
    OCLogV(cat, 0, fmt, a);
    va_end(a);
}

void OCLogInfo(OCLogCategory cat, NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    OCLogV(cat, 1, fmt, a);
    va_end(a);
}

void OCLogWarn(OCLogCategory cat, NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    OCLogV(cat, 2, fmt, a);
    va_end(a);
}

void OCLogError(OCLogCategory cat, NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    OCLogV(cat, 3, fmt, a);
    va_end(a);
}
