IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
YOSYS ?= yosys
NEXTPNR ?= yowasp-nextpnr-himbaechel-gowin
PYTHON ?= python3
BUILD_DIR ?= ../build/phy
INIT_HZ ?= 55000000
SIM_DELAY ?= 0

MIPI = ../mipi_tx
INIT = ../init_sequencer
INIT_HEX = $(abspath $(INIT)/src/init_mem.hex)
ROM = ../build/init_sequencer/init_mem_table.vh
RTL = $(wildcard src/*.v */src/*.v $(MIPI)/src/*.v $(MIPI)/*/src/*.v \
	$(INIT)/src/*.v ../video_source/src/*.v) ../motor_lpdt/src/reg_0.v
PLL_MODEL = clock_gen/TB/rpll_model.v
LOCAL_IO = clock_ddr/TB/primitives_model.v hs_serializer/TB/oser8_model.v dphy_pads/TB/primitives_model.v
ifdef GOWIN_SIM
IO_MODELS = $(BUILD_DIR)/gowin_io.v
VENDOR_DEFINE = -DGOWIN_VENDOR_SIM
SIM_LIB = gowin
else
IO_MODELS = $(LOCAL_IO)
SIM_LIB = local
endif
TB_TOP = mipi_tx_TB
TB = $(MIPI)/TB/$(TB_TOP).v
TB_EXEC = $(BUILD_DIR)/pads_$(SIM_LIB)_$(INIT_HZ)_$(SIM_DELAY).out
FST = $(BUILD_DIR)/phy_integration.fst
VERIFY = PYTHONPATH=.. $(PYTHON) dphy_pads/tools/verify_route.py

.DELETE_ON_ERROR:
.PHONY: test sim wave synth route route-direct route-delay audit audit-direct audit-delay
.SECONDARY: $(BUILD_DIR)/direct/probe.json $(BUILD_DIR)/delay/probe.json

test: $(TB_EXEC)
	cd "$(BUILD_DIR)" && $(VVP) "$(notdir $(TB_EXEC))" "+init_hex=$(INIT_HEX)"

sim: $(TB_EXEC)
	cd "$(BUILD_DIR)" && $(VVP) "$(notdir $(TB_EXEC))" -fst "+init_hex=$(INIT_HEX)" +waves
	$(MAKE) wave

wave:
	@test -s "$(FST)" || { echo "Faltan ondas en $(FST). Ejecuta make sim."; exit 1; }
	$(GTKWAVE) "$(FST)"

$(ROM): $(INIT_HEX) $(INIT)/tools/gen_init_mem_table.py $(INIT)/Makefile
	$(MAKE) -C "$(INIT)" rom BUILD_DIR="$(abspath $(@D))"

ifdef GOWIN_SIM
# Mantener la rPLL del banco para poder inyectar una pérdida sin bajar LOCK.
$(BUILD_DIR)/gowin_io.v: $(GOWIN_SIM) Makefile
	mkdir -p "$(@D)"
	awk '/^`timescale/ {print; next} \
		/^[[:space:]]*module[[:space:]]/ {copy = ($$2 ~ /^(GSR|OSER8|OSER4|CLKDIV|IODELAY|TBUF|TLVDS_TBUF)(\(|$$)/)} \
		copy {print} /^[[:space:]]*endmodule/ {copy = 0}' "$<" > "$@"
endif

$(TB_EXEC): $(TB) TB/check_hs_pads.vh $(RTL) $(ROM) $(PLL_MODEL) $(IO_MODELS) Makefile
	mkdir -p "$(@D)"
	$(IVERILOG) -g2012 -Wall -Wno-timescale -DPHY_GOWIN $(VENDOR_DEFINE) \
		-I"$(dir $(ROM))" -ITB -s $(TB_TOP) -P$(TB_TOP).INIT_HZ=$(INIT_HZ) \
		-P$(TB_TOP).DELAY=$(SIM_DELAY) -o "$@" $(TB) $(RTL) $(PLL_MODEL) $(IO_MODELS)

synth: $(BUILD_DIR)/direct/probe.json $(BUILD_DIR)/delay/probe.json
$(BUILD_DIR)/direct/probe.json: DELAY=0
$(BUILD_DIR)/delay/probe.json: DELAY=1
# La inferencia SP para la ROM de init invierte CLK_BYTE con LUT en P&R.
# Mantener la ROM en lógica en esta sonda para conservar la red de reloj.
$(BUILD_DIR)/direct/probe.json $(BUILD_DIR)/delay/probe.json: $(RTL) tools/route_probe.v $(ROM) Makefile
	mkdir -p "$(@D)"
	$(YOSYS) -Q -q -l "$(@D)/synth.log" \
		-p 'read_verilog -I$(dir $(ROM)) $(RTL) tools/route_probe.v; chparam -set DELAY $(DELAY) route_probe; synth_gowin -family gw2a -nobram -top route_probe -json "$@"'

route: route-direct route-delay
route-direct: $(BUILD_DIR)/direct/probe_routed.json
	$(VERIFY) "$(BUILD_DIR)/direct" direct --phy-prefix link.
route-delay: $(BUILD_DIR)/delay/probe_routed.json
	$(VERIFY) "$(BUILD_DIR)/delay" delay --phy-prefix link.

audit: audit-direct audit-delay
audit-direct: $(BUILD_DIR)/direct/probe_routed.json
	$(VERIFY) "$(BUILD_DIR)/direct" direct --phy-prefix link. --fuses
audit-delay: $(BUILD_DIR)/delay/probe_routed.json
	$(VERIFY) "$(BUILD_DIR)/delay" delay --phy-prefix link. --fuses

$(BUILD_DIR)/%/probe_routed.json: $(BUILD_DIR)/%/probe.json dphy_pads/tools/route_probe.cst tools/route_probe.sdc
	$(NEXTPNR) --device GW2AR-LV18EQ144PC8/I7 --vopt family=GW2A-18C \
		--vopt cst=dphy_pads/tools/route_probe.cst --vopt disable_gp_clock_routing \
		--sdc tools/route_probe.sdc --json "$<" --write "$@" --log "$(@D)/probe.log" \
		--report "$(@D)/timing.json" --detailed-timing-report
