ARCHS := arm64
TARGET := iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME := roothide
include $(THEOS)/makefiles/common.mk
TOOL_NAME := dkviewphone-device-test
dkviewphone-device-test_FILES := main.mm
dkviewphone-device-test_USE_MODULES := 0
dkviewphone-device-test_CFLAGS := -fobjc-arc
dkviewphone-device-test_CCFLAGS := -std=c++20
dkviewphone-device-test_FRAMEWORKS := Foundation UIKit
dkviewphone-device-test_LDFLAGS := -lroothide
dkviewphone-device-test_CODESIGN_FLAGS := -Stest.entitlements
include $(THEOS_MAKE_PATH)/tool.mk
