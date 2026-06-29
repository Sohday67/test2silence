# =============================================================================
#  YTLiteSkipSilence — Skip Silence extension for YTLite (YouTube)
#
#  Port of Overcast's OCAudio silence-skipping engine, repackaged as a
#  YTLite extension. Built with Theos / Logos.
# =============================================================================

TARGET               := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES := YouTube

# Build for arm64 only. arm64e is only used on A12+ devices with KTRR, and
# building arm64e on Linux requires cctools-port (Apple's ld64 doesn't ship
# for Linux). arm64 dylibs load and run fine on arm64e devices via the
# arm64e compatibility shim that MobileSubstrate ships with.
ARCHS                = arm64
TARGET_IPHONEOS_DEPLOYMENT_VERSION = 15.0
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
	-Wno-incompatible-pointer-types-discards-qualifiers \
	-Wno-unguarded-availability-new \
	-I$(THEOS_PROJECT_DIR)/Sources \
	-I$(THEOS_PROJECT_DIR)/Preferences

YTLiteSkipSilence_LDFLAGS = \
	-fuse-ld=lld \
	-Wl,-segalign,4000

# Install the YTLite extension descriptor and PreferenceLoader bundle
# alongside the dylib so YTLite / Settings.app can discover us at runtime.
before-package::
	@mkdir -p $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries
	@mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/YTLiteSkipSilenceSettings.bundle
	@cp $(THEOS_PROJECT_DIR)/YTLiteSkipSilenceExtension.plist $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/YTLiteSkipSilenceExtension.plist
	@cp $(THEOS_PROJECT_DIR)/Preferences/Root.plist     $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/YTLiteSkipSilenceSettings.bundle/Root.plist
	@cp $(THEOS_PROJECT_DIR)/Preferences/RootPane.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/YTLiteSkipSilenceSettings.bundle/RootPane.plist 2>/dev/null || true

include $(THEOS_MAKE_PATH)/tweak.mk
