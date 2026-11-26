IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
BUILD_DIR ?= ../build/mipi_tx
SIM_PROFILE ?= 1

INIT_DIR = ../init_sequencer
INIT_HEX = $(abspath $(INIT_DIR)/src/init_mem.hex)
ROM_DIR = ../build/init_sequencer
ROM = $(ROM_DIR)/init_mem_table.vh
RTL = $(wildcard src/*.v link_fsm/src/*.v lp_tx/src/*.v hs_packer/src/*.v phy_if/src/*.v) \
	$(wildcard $(INIT_DIR)/src/*.v ../video_source/src/*.v) ../motor_lpdt/src/reg_0.v
TB_TOP = mipi_tx_TB
TB = TB/$(TB_TOP).v TB/mipi_tx_phy_model.v
FST = $(BUILD_DIR)/$(TB_TOP).fst

.DELETE_ON_ERROR:
.PHONY: test sim wave compile
test: compile
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP)_p0.out "+init_hex=$(INIT_HEX)"
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP)_p1.out "+init_hex=$(INIT_HEX)"

sim: $(BUILD_DIR)/$(TB_TOP)_p$(SIM_PROFILE).out
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP)_p$(SIM_PROFILE).out -fst "+init_hex=$(INIT_HEX)" +waves
	$(MAKE) wave

wave:
	@test -s "$(FST)" || { echo "Faltan ondas en $(FST). Ejecuta make sim."; exit 1; }
	$(GTKWAVE) "$(FST)"

compile: $(BUILD_DIR)/$(TB_TOP)_p0.out $(BUILD_DIR)/$(TB_TOP)_p1.out

$(ROM): $(INIT_HEX) $(INIT_DIR)/tools/gen_init_mem_table.py $(INIT_DIR)/Makefile
	$(MAKE) -C "$(INIT_DIR)" rom BUILD_DIR="$(abspath $(ROM_DIR))"

$(BUILD_DIR)/$(TB_TOP)_p%.out: $(TB) $(RTL) $(ROM) Makefile
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -Wno-timescale -I"$(ROM_DIR)" -s $(TB_TOP) \
		-P$(TB_TOP).PROFILE=$* -o "$@" $(TB) $(RTL)
