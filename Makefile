# =============================================================================
#  YTLiteSkipSilence — Skip Silence extension for YTLite (YouTube)
#
#  Port of Overcast's OCAudio silence-skipping engine, repackaged as a
#  YTLite extension. Built with Theos / Logos.
# =============================================================================

TARGET               := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES := YouTube

ARCHS                = arm64 arm64e
TARGET_IPHONEOS_DEPLOYMENT_VERSION = 14.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME           = YTLiteSkipSilence

# -----------------------------------------------------------------------------
#  Source layout
# -----------------------------------------------------------------------------
YTLiteSkipSilence_FILES = \
        Tweak.x \
        Sources/OCLog.m \
        Sources/OCSettings.m \
        Sources/OCAudioPlaybackSpeed.m \
        Sources/OCVoiceBoostConfiguration.m \
        Sources/OCSilenceDetector.m \
        Sources/OCAudioClassifier.m \
        Sources/OCSmartSpeedTracker.m \
        Sources/OCSkipSilenceEngine.m \
        Sources/MTAudioProcessingTapStubs.m \
        Preferences/YTLiteSkipSilenceSettings.x

# -----------------------------------------------------------------------------
#  Frameworks
#  - AVFoundation / AVFAudio : AVPlayer, AVAudioEngine, AVAudioPCMBuffer
#  - AudioToolbox            : MTAudioProcessingTap (private, stubbed)
#  - SoundAnalysis           : SNClassifier for music detection (Overcast port)
#  - MediaToolbox            : MTAudioProcessingTap callbacks
#  - CoreMedia               : CMSampleBuffer, CMTime
# -----------------------------------------------------------------------------
YTLiteSkipSilence_FRAMEWORKS = \
        AVFoundation \
        AVFAudio \
        AudioToolbox \
        MediaToolbox \
        CoreMedia \
        SoundAnalysis \
        Accelerate

YTLiteSkipSilence_CFLAGS = \
        -fobjc-arc \
        -Wno-deprecated-declarations \
        -Wno-unused-variable \
        -Wno-unused-function \
        -I$(THEOS_PROJECT_DIR)/Sources \
        -I$(THEOS_PROJECT_DIR)/Preferences \
        -DYTLITE_SKIP_SILENCE_VERSION=\"1.0.0\"

YTLiteSkipSilence_LDFLAGS = \
        -Wl,-segalign,4000

# Bundle ID we hook into (YouTube) plus YTLite for extension handshake
YTLiteSkipSilence_PRIVATE_FRAMEWORKS = \
        YouTube \
        YouTubeUI \
        BackBoardServices

# -----------------------------------------------------------------------------
#  Resources — install the PreferenceLoader bundle alongside the dylib so
#  Settings.app picks up "YTLiteSkipSilence" automatically.
# -----------------------------------------------------------------------------
YTLiteSkipSilence_BUNDLES = \
        PreferencesBundle

# The preferences bundle is built from the Preferences/ directory and installed
# at /Library/PreferenceLoader/Preferences/YTLiteSkipSilenceSettings.bundle/
before-package::
        @mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/YTLiteSkipSilenceSettings.bundle
        @cp $(THEOS_PROJECT_DIR)/Preferences/Root.plist     $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/YTLiteSkipSilenceSettings.bundle/Root.plist
        @cp $(THEOS_PROJECT_DIR)/Preferences/RootPane.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/YTLiteSkipSilenceSettings.bundle/RootPane.plist 2>/dev/null || true

# Install the YTLite extension descriptor next to the dylib so YTLite can
# discover us at runtime.
before-package::
        @cp $(THEOS_PROJECT_DIR)/YTLiteSkipSilenceExtension.plist $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/YTLiteSkipSilenceExtension.plist

include $(THEOS_MAKE_PATH)/tweak.mk
