ifeq ($(strip $(PVSNESLIB_HOME)),)
$(error Set PVSNESLIB_HOME to the PVSnesLib root)
endif
export ROMNAME := retro_sm_snes
export ROMTITLE := RETRO SM
include $(PVSNESLIB_HOME)/devkitsnes/snes_rules
all: $(ROMNAME).sfc
