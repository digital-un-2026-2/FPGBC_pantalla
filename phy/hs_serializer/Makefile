IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
YOSYS ?= yosys
NEXTPNR ?= yowasp-nextpnr-himbaechel-gowin
PYTHON ?= python3
BUILD_DIR ?= ../../build/hs_serializer
OSER_MODEL ?= TB/oser8_model.v
RTL = src/hs_serializer.v
TB_TOP = hs_serializer_TB
TB = TB/$(TB_TOP).v $(OSER_MODEL)
VENDOR_DEFINE = $(if $(filter TB/oser8_model.v,$(OSER_MODEL)),,-DGOWIN_VENDOR_SIM)
FST = $(BUILD_DIR)/$(TB_TOP).fst
PROBE = tools/route_probe.v ../clock_gen/src/clock_gen.v

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
	$(IVERILOG) -g2012 -Wall -Wno-timescale $(VENDOR_DEFINE) -s $(TB_TOP) -o "$@" $(TB) $(RTL)

synth: $(BUILD_DIR)/probe.json

$(BUILD_DIR)/probe.json: $(RTL) $(PROBE) Makefile
	mkdir -p "$(BUILD_DIR)"
	$(YOSYS) -Q -q -l "$(BUILD_DIR)/synth.log" \
		-p 'read_verilog $(RTL) $(PROBE); synth_gowin -family gw2a -top route_probe -json "$@"'

route: synth
	$(NEXTPNR) --device GW2AR-LV18EQ144PC8/I7 --vopt family=GW2A-18C \
		--vopt cst=tools/route_probe.cst --vopt disable_gp_clock_routing \
		--sdc tools/route_probe.sdc --json "$(BUILD_DIR)/probe.json" \
		--write "$(BUILD_DIR)/probe_routed.json" --log "$(BUILD_DIR)/probe.log" \
		--report "$(BUILD_DIR)/timing.json" --detailed-timing-report
	$(PYTHON) tools/verify_route.py "$(BUILD_DIR)"
