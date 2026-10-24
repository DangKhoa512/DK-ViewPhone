ARCHS := arm64
TARGET := iphone:clang:16.5:15.0
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME := DKScreenStreamPrefs
DKScreenStreamPrefs_FILES := SSPrefs.mm
DKScreenStreamPrefs_CFLAGS := -fobjc-arc
DKScreenStreamPrefs_CCFLAGS := -std=c++20
DKScreenStreamPrefs_FRAMEWORKS := UIKit Security
DKScreenStreamPrefs_PRIVATE_FRAMEWORKS := Preferences
DKScreenStreamPrefs_INSTALL_PATH := /Library/PreferenceBundles
DKScreenStreamPrefs_CODESIGN_FLAGS := -S
include $(THEOS_MAKE_PATH)/bundle.mk
