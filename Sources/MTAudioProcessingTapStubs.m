//
//  MTAudioProcessingTapStubs.m
//  YTLiteSkipSilence
//
//  MTAudioProcessingTap lives in MediaToolbox and is the only supported way
//  to inspect AVPlayer's audio buffers in real time on iOS (you attach the
//  tap to an AVAssetTrack's audio mix input). The header is not in the public
//  SDK, so we declare just enough of the API here to use it.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <AudioToolbox/AudioToolbox.h>
#import <MediaToolbox/MediaToolbox.h>
#import "OCLog.h"

// We can't directly link to MTAudioProcessingTapCreate on the device SDK
// because the symbol is in MediaToolbox (private-but-loadable). The header
// below mirrors the one Apple ships in the SDK on macOS — the iOS runtime
// exports the same symbols.

typedef struct OpaqueMTAudioProcessingTap *MTAudioProcessingTapRef;

typedef enum {
    kMTAudioProcessingTapCreationFlag_PreEffects   = 1u << 0,
    kMTAudioProcessingTapCreationFlag_PostEffects  = 1u << 1,
} MTAudioProcessingTapCreationFlags;

typedef void (*MTAudioProcessingTapInitCallback)(
    void *clientHandle,
    void *tapStorage,
    CMAudioFormatDescriptionRef formatDescription,
    MTAudioProcessingTapMutableStorageRef *tapStorageOut);

typedef void (*MTAudioProcessingTapFinalizeCallback)(void *tapStorage);
typedef void (*MTAudioProcessingTapPrepareCallback)(
    void *tapStorage,
    CMItemCount maxNumberFrames);
typedef void (*MTAudioProcessingTapUnprepareCallback)(void *tapStorage);
typedef void (*MTAudioProcessingTapProcessCallback)(
    void *tapStorage,
    CMItemCount numberFrames,
    MTAudioProcessingTapRef tap,
    CMItemCount numberFramesOut,
    CMAudioBufferList *bufferListInOut,
    CMTime *timeIn,
    CMTime *timeOut,
    void *refCon);

typedef struct {
    uint32_t version;
    void *clientHandle;
    MTAudioProcessingTapInitCallback      init;
    MTAudioProcessingTapFinalizeCallback  finalize;
    MTAudioProcessingTapPrepareCallback   prepare;
    MTAudioProcessingTapUnprepareCallback unprepare;
    MTAudioProcessingTapProcessCallback   process;
} MTAudioProcessingTapCallbacks;

extern OSStatus MTAudioProcessingTapCreate(
    CFAllocatorRef allocator,
    const MTAudioProcessingTapCallbacks *callbacks,
    MTAudioProcessingTapCreationFlags flags,
    MTAudioProcessingTapRef *tapOut) __attribute__((weak_import));

extern CFStringRef MTAudioProcessingTapGetUUID(MTAudioProcessingTapRef tap) __attribute__((weak_import));

// Stubs are intentionally empty — this file exists purely so that when the
// framework is not loadable at compile time, we still have a translation unit
// the linker can see. At runtime we dlsym() the symbols from MediaToolbox.
__attribute__((constructor))
static void OCMTTapStubsCtor(void) {
    // No-op. We just need a translation unit for the .m file to be linked.
}
