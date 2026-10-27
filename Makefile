TARGET := iphone:clang:15.5:15.0
ARCHS := arm64
INSTALL_TARGET_PROCESSES := SpringBoard

THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := CelosiaDepth

CelosiaDepth_FILES := \
	Tweak.x \
	Sources/CDWallpaperDetector.m \
	Sources/CDDepthProcessor.m \
	Sources/CDDepthOverlayView.m \
	Sources/CDCacheManager.m \
	Sources/CDPreferences.m

CelosiaDepth_CFLAGS := -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations
CelosiaDepth_FRAMEWORKS := UIKit CoreGraphics CoreImage QuartzCore Foundation
CelosiaDepth_PRIVATE_FRAMEWORKS := SpringBoardFoundation
CelosiaDepth_LIBRARIES := substrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "sbreload || killall -9 SpringBoard"
