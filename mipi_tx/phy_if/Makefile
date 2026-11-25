IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
BUILD_DIR ?= ../../build/phy_if
RTL = $(wildcard src/*.v) ../../motor_lpdt/src/reg_0.v
TB_TOP = phy_if_TB
TB = TB/$(TB_TOP).v
FST = $(BUILD_DIR)/$(TB_TOP).fst

.PHONY: test sim wave compile
test: compile
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP).out

sim: compile
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP).out -fst +waves
	$(MAKE) wave

wave:
	@test -s "$(FST)" || { echo "Faltan ondas en $(FST). Ejecuta make sim."; exit 1; }
	$(GTKWAVE) "$(FST)"

compile:
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -Wno-timescale -s $(TB_TOP) -o "$(BUILD_DIR)/$(TB_TOP).out" $(TB) $(RTL)
