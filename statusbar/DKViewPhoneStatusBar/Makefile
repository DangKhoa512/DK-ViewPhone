ARCHS := arm64
TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := DKViewPhoneStatusBar
DKViewPhoneStatusBar_FILES := Tweak.xm
DKViewPhoneStatusBar_CFLAGS := -fobjc-arc
DKViewPhoneStatusBar_FRAMEWORKS := Foundation UIKit

ifeq ($(THEOS_DEVICE_SIMULATOR),1)
DKViewPhoneStatusBar_CODESIGN_FLAGS += -f -s -
else
DKViewPhoneStatusBar_CODESIGN_FLAGS += -S
endif

include $(THEOS_MAKE_PATH)/tweak.mk
