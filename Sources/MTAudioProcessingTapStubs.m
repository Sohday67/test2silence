//
//  MTAudioProcessingTapStubs.m
//  YTLiteSkipSilence
//
//  This translation unit exists so that the MediaToolbox framework is linked
//  into the final dylib. The actual MTAudioProcessingTap API is declared in
//  <MediaToolbox/MTAudioProcessingTap.h> (a public iOS 6+ header) and is
//  used directly from OCSkipSilenceEngine.m.
//
//  Historically, MTAudioProcessingTap was a private framework and required
//  manual declaration. As of iOS 6 the header is in the public SDK, so this
//  file is now empty — it exists only to force the linker to link
//  MediaToolbox.framework.
//

#import <MediaToolbox/MediaToolbox.h>

// No code needed — the import above is enough to pull in the framework.
