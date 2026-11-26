IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
YOSYS ?= yosys
NEXTPNR ?= yowasp-nextpnr-himbaechel-gowin
PYTHON ?= python3
BUILD_DIR ?= ../../build/clock_gen
RTL = src/clock_gen.v
TB_TOP = clock_gen_TB
TB = TB/$(TB_TOP).v TB/rpll_model.v
FST = $(BUILD_DIR)/$(TB_TOP).fst
SYNTH_JSON = $(BUILD_DIR)/clock_gen.json

.DELETE_ON_ERROR:
.PHONY: test sim wave compile synth route
test: compile
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP).out

sim: compile
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP).out -fst +waves
	$(MAKE) wave

wave:
	@test -s "$(FST)" || { echo "Faltan ondas en $(FST). Ejecuta make sim."; exit 1; }
	$(GTKWAVE) "$(FST)"

compile: $(BUILD_DIR)/$(TB_TOP).out

$(BUILD_DIR)/$(TB_TOP).out: $(TB) $(RTL) Makefile
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -Wno-timescale -s $(TB_TOP) -o "$@" $(TB) $(RTL)

synth: $(SYNTH_JSON)

$(SYNTH_JSON): $(RTL) Makefile
	mkdir -p "$(BUILD_DIR)"
	$(YOSYS) -Q -q -l "$(BUILD_DIR)/synth.log" \
		-p 'read_verilog $(RTL); synth_gowin -family gw2a -noiopads -top clock_gen -json "$@"'

route: synth
	$(PYTHON) tools/route_probe.py prepare "$(BUILD_DIR)"
	cd "$(BUILD_DIR)" && $(NEXTPNR) -q --device GW2AR-LV18EQ144PC8/I7 --vopt family=GW2A-18C \
		--vopt cst=probe.cst --vopt disable_gp_clock_routing \
		--sdc probe.sdc --json probe.json --write probe_routed.json --log probe.log
	$(PYTHON) tools/route_probe.py verify "$(BUILD_DIR)"
