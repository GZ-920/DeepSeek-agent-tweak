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
                 src/SelfTest.m \
                 src/Probe.m \
                 src/Sidebar.m \
                 src/NativeInsert.m \
                 src/NativeSidebar.m \
                 src/AgentEditor.m
DSAAgent_CFLAGS = -fobjc-arc -I src -Wno-unused-function -Wno-deprecated-declarations \
                  -DDSA_SELFTEST=1 -DDSA_TREE_FALLBACK=1 -DDSA_TABLE_HOOK=1
DSAAgent_FRAMEWORKS = UIKit Foundation
DSAAgent_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk
