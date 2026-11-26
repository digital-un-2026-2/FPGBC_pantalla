IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
BUILD_DIR ?= ../build/video_source
SIM_PROFILE ?= 1
RTL = $(wildcard src/*.v)
TB_TOP = video_source_TB
TB = TB/$(TB_TOP).v
FST = $(BUILD_DIR)/$(TB_TOP).fst

.DELETE_ON_ERROR:
.PHONY: test sim wave compile
test: compile
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP)_p0.out
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP)_p1.out

sim: $(BUILD_DIR)/$(TB_TOP)_p$(SIM_PROFILE).out
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP)_p$(SIM_PROFILE).out -fst +waves
	$(MAKE) wave

wave:
	@test -s "$(FST)" || { echo "Faltan ondas en $(FST). Ejecuta make sim."; exit 1; }
	$(GTKWAVE) "$(FST)"

compile: $(BUILD_DIR)/$(TB_TOP)_p0.out $(BUILD_DIR)/$(TB_TOP)_p1.out

$(BUILD_DIR)/$(TB_TOP)_p%.out: $(TB) $(RTL) Makefile
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -Wno-timescale -s $(TB_TOP) -P$(TB_TOP).PROFILE=$* -o "$@" $(TB) $(RTL)
