ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RespringProgress
RespringProgress_FILES = Tweak.xm

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 backboardd"
