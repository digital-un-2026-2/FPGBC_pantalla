PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
YOSYS ?= yosys
NEXTPNR ?= yowasp-nextpnr-himbaechel-gowin

ROOT := $(abspath ..)
BUILD := $(ROOT)/build/fpgbc_white
PHY := $(ROOT)/phy
MIPI := $(ROOT)/mipi_tx
ROM := $(ROOT)/init_sequencer/src/init_mem.hex
ROM_INCLUDE := $(ROOT)/build/init_sequencer
VARIANT ?= direct
ifneq ($(VARIANT),$(filter $(VARIANT),direct delay))
$(error VARIANT debe ser direct o delay)
endif
SDC := $(ROOT)/gateware/targets/fpgbc_white.sdc
TOP := fpgbc_white
RTL := $(wildcard $(PHY)/src/*.v $(PHY)/*/src/*.v $(MIPI)/src/*.v $(MIPI)/*/src/*.v \
	$(ROOT)/init_sequencer/src/*.v $(ROOT)/video_source/src/*.v) \
	$(ROOT)/motor_lpdt/src/reg_0.v $(ROOT)/gateware/cores/fpgbc_white_control.v
MODELS := $(PHY)/clock_gen/TB/rpll_model.v $(PHY)/clock_ddr/TB/primitives_model.v \
	$(PHY)/hs_serializer/TB/oser8_model.v $(PHY)/dphy_pads/TB/primitives_model.v \
	$(PHY)/phy_supervisor/TB/osc_model.v $(ROOT)/gateware/tests/gowin_pad_models.v
TB := $(MIPI)/TB/mipi_tx_TB.v
TEST_INCLUDES := $(PHY)/TB/check_hs_pads.vh $(PHY)/phy_supervisor/TB/supervised_link.vh \
	$(wildcard $(ROOT)/gateware/tests/white_target_*.vh)

.PHONY: test test-final-wait test-white test-bars sim wave synth route audit
.DELETE_ON_ERROR:
.PRECIOUS: $(BUILD)/%/$(TOP).v $(BUILD)/%/$(TOP).ys $(BUILD)/%/$(TOP).cst
.SECONDARY: $(BUILD)/$(VARIANT)/$(TOP).json

test: test-white test-bars

test-final-wait: VVP_ARGS = +short_waits
test-final-wait: test-white test-bars

test-white: $(BUILD)/$(VARIANT)/test.out
	cd "$(BUILD)/$(VARIANT)" && $(VVP) -i test.out "+init_hex=$(ROM)" $(VVP_ARGS)

test-bars: $(BUILD)/bars/test.out
	cd "$(BUILD)/bars" && $(VVP) -i test.out "+init_hex=$(ROM)" $(VVP_ARGS)

sim: $(BUILD)/$(VARIANT)/test.out
	cd "$(BUILD)/$(VARIANT)" && $(VVP) test.out -fst "+init_hex=$(ROM)" +waves
	$(MAKE) wave

wave:
	@test -s "$(BUILD)/$(VARIANT)/$(TOP).fst" || { echo "Genera las ondas con make sim"; exit 1; }
	$(GTKWAVE) "$(BUILD)/$(VARIANT)/$(TOP).fst"

$(ROM_INCLUDE)/init_mem_table.vh: $(ROM) ../init_sequencer/tools/gen_init_mem_table.py ../init_sequencer/Makefile
	$(MAKE) -C ../init_sequencer rom

$(BUILD)/%/$(TOP).v $(BUILD)/%/$(TOP).ys $(BUILD)/%/$(TOP).cst &: targets/fpgbc_white.py platforms/fpgbc.py $(RTL) Makefile
	cd "$(ROOT)" && $(PYTHON) -m gateware.targets.fpgbc_white --output-dir "$(@D)" \
		$(if $(filter bars,$*),--bars) $(if $(filter delay,$*),--delay)

$(BUILD)/%/test.out: $(BUILD)/%/$(TOP).v $(RTL) $(MODELS) $(TB) $(TEST_INCLUDES) $(ROM_INCLUDE)/init_mem_table.vh
	$(IVERILOG) -g2012 -Wall -Wno-timescale -DFPGBC_WHITE -DPHY_GOWIN -DPHY_SUPERVISED \
		-I"$(ROM_INCLUDE)" -I"$(PHY)/TB" -I"$(PHY)/phy_supervisor/TB" -Itests \
		-s mipi_tx_TB -Pmipi_tx_TB.WHITE=$(if $(filter bars,$*),0,1) \
		-o "$@" $(TB) $(MODELS) "$(BUILD)/$*/$(TOP).v" $(RTL)

synth: $(BUILD)/$(VARIANT)/$(TOP).json
route: $(BUILD)/$(VARIANT)/$(TOP)_routed.json
audit: route
	cd "$(ROOT)" && $(PYTHON) -m gateware.tests.review_white "$(BUILD)/$(VARIANT)" "$(VARIANT)"

$(BUILD)/%/$(TOP).json: $(BUILD)/%/$(TOP).v $(BUILD)/%/$(TOP).ys $(ROM_INCLUDE)/init_mem_table.vh
	cd "$(@D)" && $(YOSYS) -Q -q -l synth.log -s $(TOP).ys

$(BUILD)/%/$(TOP).sdc: $(SDC)
	mkdir -p "$(@D)"
	cp "$<" "$@"

$(BUILD)/%/$(TOP)_routed.json: $(BUILD)/%/$(TOP).json $(BUILD)/%/$(TOP).cst $(BUILD)/%/$(TOP).sdc
	cd "$(@D)" && $(NEXTPNR) --device GW2AR-LV18EQ144PC8/I7 \
		--vopt family=GW2A-18C --vopt cst=$(TOP).cst --vopt disable_gp_clock_routing \
		--sdc "$(TOP).sdc" --json "$(TOP).json" --write "$(@F)" --log route.log --report timing.json
