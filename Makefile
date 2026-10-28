TARGET := iphone:clang:15.6:15.0
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

BUNDLE_NAME := CelosiaDepthPrefs
CelosiaDepthPrefs_FILES := Preferences/CDRootListController.m
CelosiaDepthPrefs_FRAMEWORKS := UIKit
CelosiaDepthPrefs_PRIVATE_FRAMEWORKS := Preferences
CelosiaDepthPrefs_RESOURCE_FILES := Resources/Root.plist
CelosiaDepthPrefs_INSTALL_PATH := /Library/PreferenceBundles
CelosiaDepthPrefs_CFLAGS := -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "sbreload || killall -9 SpringBoard"
