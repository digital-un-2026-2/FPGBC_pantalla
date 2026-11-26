IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
YOSYS ?= yosys
NEXTPNR ?= yowasp-nextpnr-himbaechel-gowin
PYTHON ?= python3
BUILD_DIR ?= ../../build/clock_ddr
PRIMITIVES ?= TB/primitives_model.v
RTL = src/clock_ddr.v
TB_TOP = clock_ddr_TB
VENDOR_DEFINE = $(if $(filter TB/primitives_model.v,$(PRIMITIVES)),,-DGOWIN_VENDOR_SIM)
FST = $(BUILD_DIR)/$(TB_TOP).fst
PROBE = tools/route_probe.v ../clock_gen/src/clock_gen.v ../hs_serializer/src/hs_serializer.v

.DELETE_ON_ERROR:
.PHONY: test sim wave synth route route-direct route-delay
test: $(BUILD_DIR)/$(TB_TOP).out
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP).out

sim: $(BUILD_DIR)/$(TB_TOP).out
	cd "$(BUILD_DIR)" && $(VVP) $(TB_TOP).out -fst +waves
	$(MAKE) wave

wave:
	@test -s "$(FST)" || { echo "Faltan ondas en $(FST). Ejecuta make sim."; exit 1; }
	$(GTKWAVE) "$(FST)"

$(BUILD_DIR)/$(TB_TOP).out: TB/$(TB_TOP).v $(PRIMITIVES) $(RTL) Makefile
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -Wno-timescale $(VENDOR_DEFINE) -s $(TB_TOP) -o "$@" TB/$(TB_TOP).v "$(PRIMITIVES)" $(RTL)

synth: $(BUILD_DIR)/direct/probe.json $(BUILD_DIR)/delay/probe.json

$(BUILD_DIR)/direct/probe.json: DELAY=0
$(BUILD_DIR)/delay/probe.json: DELAY=1
$(BUILD_DIR)/direct/probe.json $(BUILD_DIR)/delay/probe.json: $(RTL) $(PROBE) Makefile
	mkdir -p "$(@D)"
	$(YOSYS) -Q -q -l "$(@D)/synth.log" \
		-p 'read_verilog $(RTL) $(PROBE); chparam -set DELAY $(DELAY) route_probe; synth_gowin -family gw2a -top route_probe -json "$@"'

route: route-direct route-delay
route-direct: $(BUILD_DIR)/direct/probe_routed.json
	$(PYTHON) tools/verify_route.py "$(BUILD_DIR)/direct" direct
route-delay: $(BUILD_DIR)/delay/probe_routed.json
	$(PYTHON) tools/verify_route.py "$(BUILD_DIR)/delay" delay

$(BUILD_DIR)/%/probe_routed.json: $(BUILD_DIR)/%/probe.json tools/route_probe.cst tools/route_probe.sdc
	$(NEXTPNR) --device GW2AR-LV18EQ144PC8/I7 --vopt family=GW2A-18C \
		--vopt cst=tools/route_probe.cst --vopt disable_gp_clock_routing \
		--sdc tools/route_probe.sdc --json "$<" --write "$@" --log "$(@D)/probe.log" \
		--report "$(@D)/timing.json" --detailed-timing-report
