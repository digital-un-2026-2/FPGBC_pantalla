PYTHON ?= python
IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
BUILD_DIR ?= ../build/init_sequencer
SIM_PROFILE ?= 1
RTL = $(wildcard src/*.v)
HEX = src/init_mem.hex
GEN_ROM = tools/gen_init_mem_table.py
ROM = $(BUILD_DIR)/init_mem_table.vh
TB_TOP = init_sequencer_TB
TB = TB/$(TB_TOP).v
FST = $(BUILD_DIR)/$(TB_TOP).fst

.DELETE_ON_ERROR:
.PHONY: test sim wave compile rom
test: compile
	$(VVP) "$(BUILD_DIR)/$(TB_TOP)_p0.out"
	$(VVP) "$(BUILD_DIR)/$(TB_TOP)_p1.out"

sim: $(BUILD_DIR)/$(TB_TOP)_p$(SIM_PROFILE).out
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP)_p$(SIM_PROFILE).out -fst +waves
	$(MAKE) wave

wave:
	@test -s "$(FST)" || { echo "Faltan ondas en $(FST). Ejecuta make sim."; exit 1; }
	$(GTKWAVE) "$(FST)"

compile: $(BUILD_DIR)/$(TB_TOP)_p0.out $(BUILD_DIR)/$(TB_TOP)_p1.out

rom: $(ROM)

$(ROM): $(HEX) $(GEN_ROM) Makefile
	mkdir -p "$(BUILD_DIR)"
	$(PYTHON) $(GEN_ROM) $(HEX) "$@"

$(BUILD_DIR)/$(TB_TOP)_p%.out: $(TB) $(RTL) $(ROM) Makefile
	$(IVERILOG) -g2012 -Wall -Wno-timescale -I"$(BUILD_DIR)" -s $(TB_TOP) \
		-P$(TB_TOP).PROFILE=$* -o "$@" $(TB) $(RTL)
