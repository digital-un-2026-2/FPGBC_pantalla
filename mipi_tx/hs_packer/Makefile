IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
BUILD_DIR ?= ../../build/hs_packer
RTL = $(wildcard src/*.v)
TB_TOP = hs_packer_TB
TB = TB/$(TB_TOP).v
FST = $(BUILD_DIR)/$(TB_TOP).fst
WAVE_CONFIG = $(wildcard waves/$(TB_TOP).gtkw)

.PHONY: test sim wave compile
test: compile
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP).out

sim: compile
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP).out -fst +waves
	$(MAKE) wave

wave:
	@test -s "$(FST)" || { echo "Faltan ondas en $(FST). Ejecuta make sim."; exit 1; }
	$(GTKWAVE) "$(FST)" $(WAVE_CONFIG)

compile:
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -Wno-timescale -s $(TB_TOP) -o "$(BUILD_DIR)/$(TB_TOP).out" $(TB) $(RTL)
