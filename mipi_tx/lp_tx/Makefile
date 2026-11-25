IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
BUILD_DIR ?= ../../build/lp_tx
SIM_DIV ?= 6
RTL = $(wildcard src/*.v) ../../motor_lpdt/src/reg_0.v
TB_TOP = lp_tx_TB
TB = TB/$(TB_TOP).v
FST = $(BUILD_DIR)/$(TB_TOP).fst

.PHONY: test sim wave compile
test: compile
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP)_d1.out
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP)_d6.out

sim: $(BUILD_DIR)/$(TB_TOP)_d$(SIM_DIV).out
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP)_d$(SIM_DIV).out -fst +waves
	$(MAKE) wave

wave:
	@test -s "$(FST)" || { echo "Faltan ondas en $(FST). Ejecuta make sim."; exit 1; }
	$(GTKWAVE) "$(FST)"

compile: $(BUILD_DIR)/$(TB_TOP)_d1.out $(BUILD_DIR)/$(TB_TOP)_d6.out

$(BUILD_DIR)/$(TB_TOP)_d%.out: $(TB) $(RTL) Makefile
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -Wno-timescale -s $(TB_TOP) -P$(TB_TOP).LP_DIV=$* -o "$@" $(TB) $(RTL)
