export PACKAGE_VERSION := 0.1.0
THEOS_PACKAGE_SCHEME ?= roothide
export THEOS_PACKAGE_SCHEME
ifneq ($(THEOS_PACKAGE_SCHEME),roothide)
$(error ScreenStream supports native roothide only)
endif
ifneq ($(strip $(THEBOOTSTRAP)$(THEOS_DEVICE_SIMULATOR)),)
$(error ScreenStream builds only physical-device DEBs)
endif
ARCHS := arm64
TARGET := iphone:clang:16.5:15.0
GO_EASY_ON_ME := 1
include $(THEOS)/makefiles/common.mk
TOOL_NAME := dkss-server dkss-supervisor
dkss-server_FILES := Daemon/main.mm Daemon/Controller.mm Capture/NativeCapture.mm Capture/FrameScaler.mm Encoder/JPEGEncoder.mm Streaming/StreamServer.mm
dkss-server_USE_MODULES := 0
dkss-server_CFLAGS := -fobjc-arc -Wno-deprecated-declarations
dkss-server_CCFLAGS := -std=c++20
dkss-server_FRAMEWORKS := Foundation UIKit IOSurface IOKit QuartzCore Accelerate CoreGraphics ImageIO
dkss-server_PRIVATE_FRAMEWORKS := FrontBoardServices
dkss-server_LDFLAGS := -lroothide
dkss-server_CODESIGN_FLAGS := -SDaemon/worker.entitlements
dkss-supervisor_FILES := Daemon/supervisor.mm Common/Log.mm
dkss-supervisor_USE_MODULES := 0
dkss-supervisor_CFLAGS := -fobjc-arc
dkss-supervisor_CCFLAGS := -std=c++20
dkss-supervisor_FRAMEWORKS := Foundation
dkss-supervisor_LDFLAGS := -lroothide
dkss-supervisor_CODESIGN_FLAGS := -SDaemon/supervisor.entitlements
include $(THEOS_MAKE_PATH)/tool.mk
SUBPROJECTS := Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
before-package::
	@mkdir -p "$(THEOS_STAGING_DIR)/usr/share/dk-screenstream/web" "$(THEOS_STAGING_DIR)/usr/share/doc/com.dk.screenstream"
	@cp Web/index.html Web/viewer.js Web/style.css "$(THEOS_STAGING_DIR)/usr/share/dk-screenstream/web/"
	@cp COPYING ATTRIBUTION.md "$(THEOS_STAGING_DIR)/usr/share/doc/com.dk.screenstream/"
