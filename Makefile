TARGET := iphone:clang:latest:15.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DSAAgent
DSAAgent_FILES = src/Tweak.xm \
                 src/AgentStore.m \
                 src/HookUtil.m \
                 src/AgentListController.m \
                 src/Entry.m \
                 src/Inject.m \
                 src/Trigger.m \
                 src/SelfTest.m
DSAAgent_CFLAGS = -fobjc-arc -DDSA_SELFTEST=1 -DDSA_UI_FORCE=1 -I src -Wno-unused-function -Wno-deprecated-declarations
DSAAgent_FRAMEWORKS = UIKit Foundation
DSAAgent_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk
