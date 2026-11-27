PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
YOSYS ?= yosys
NEXTPNR ?= yowasp-nextpnr-himbaechel-gowin

ROOT := $(abspath ..)
BUILD ?= $(ROOT)/build/fpgbc_frame_1168
PHY := $(ROOT)/phy
MIPI := $(ROOT)/mipi_tx
ROM := $(ROOT)/init_sequencer/src/init_mem.hex
ROM_INCLUDE := $(ROOT)/build/init_sequencer
VARIANT ?= bars
ifneq ($(VARIANT),$(filter $(VARIANT),bars white delay white-delay data-only data-timed))
	$(error VARIANT debe ser bars, white, delay, white-delay, data-only o data-timed)
endif
REVIEW_VARIANT = $(if $(filter data-only data-timed,$(VARIANT)),data-only,$(if $(filter delay white-delay,$(VARIANT)),delay,direct))
SDC := $(ROOT)/gateware/targets/fpgbc_white.sdc
DATA_ONLY_SDC := $(ROOT)/gateware/targets/fpgbc_data_only.sdc
TOP := fpgbc_white
RTL := $(wildcard $(PHY)/src/*.v $(PHY)/*/src/*.v $(MIPI)/src/*.v $(MIPI)/*/src/*.v \
	$(ROOT)/init_sequencer/src/*.v $(ROOT)/video_source/src/*.v) \
	$(ROOT)/motor_lpdt/src/reg_0.v $(ROOT)/gateware/cores/fpgbc_white_control.v
MODELS := $(PHY)/clock_gen/TB/rpll_model.v $(PHY)/clock_ddr/TB/primitives_model.v \
	$(PHY)/hs_serializer/TB/oser8_model.v $(PHY)/dphy_pads/TB/primitives_model.v \
	$(PHY)/phy_supervisor/TB/osc_model.v $(ROOT)/gateware/tests/gowin_pad_models.v
TB := $(MIPI)/TB/mipi_tx_TB.v
TEST_INCLUDES := $(PHY)/TB/check_hs_pads.vh $(PHY)/phy_supervisor/TB/supervised_link.vh \
	$(wildcard $(ROOT)/gateware/tests/white_target_*.vh) tests/frame_target_checks.vh

.PHONY: test test-final-wait test-white test-bars test-delay test-delay-white test-data-only test-data-timed test-data-timing-control test-video-fix test-backlight sim wave synth route audit fs
.DELETE_ON_ERROR:
.PRECIOUS: $(BUILD)/%/$(TOP).v $(BUILD)/%/$(TOP).ys $(BUILD)/%/$(TOP).cst $(BUILD)/%/$(TOP).sdc
.SECONDARY: $(BUILD)/$(VARIANT)/$(TOP).json

test: test-white test-bars

test-backlight:
	mkdir -p "$(BUILD)"
	$(IVERILOG) -g2012 -Wall -Wno-timescale -s backlight_control_TB \
		-o "$(BUILD)/backlight_control.out" tests/backlight_control_TB.v \
		cores/fpgbc_white_control.v $(PHY)/phy_supervisor/src/phy_supervisor_reset_sync.v
	cd "$(BUILD)" && $(VVP) backlight_control.out

test-final-wait: VVP_ARGS = +short_waits
test-final-wait: test-white test-bars

test-white: $(BUILD)/white/test.out
	cd "$(BUILD)/white" && $(VVP) -i test.out "+init_hex=$(ROM)" $(VVP_ARGS)

test-bars: $(BUILD)/bars/test.out
	cd "$(BUILD)/bars" && $(VVP) -i test.out "+init_hex=$(ROM)" $(VVP_ARGS)

test-data-only: $(BUILD)/data-only/test.out
	cd "$(BUILD)/data-only" && $(VVP) -i test.out "+init_hex=$(ROM)" +check_tinit $(VVP_ARGS)

test-data-timed: $(BUILD)/data-timed/test.out
	cd "$(BUILD)/data-timed" && $(VVP) -i test.out "+init_hex=$(ROM)" +check_tinit +check_eye $(VVP_ARGS)

test-data-timing-control: $(BUILD)/data_timing_control.out
	cd "$(BUILD)" && $(VVP) data_timing_control.out

$(BUILD)/data_timing_control.out: tests/data_timing_control_TB.v $(PHY)/phy_ctrl/src/phy_ctrl_gowin.v $(PHY)/phy_ctrl/src/phy_ctrl_guard.v Makefile
	mkdir -p "$(@D)"
	$(IVERILOG) -g2012 -Wall -Wno-timescale -s data_timing_control_TB \
		-o "$@" $< $(PHY)/phy_ctrl/src/phy_ctrl_gowin.v $(PHY)/phy_ctrl/src/phy_ctrl_guard.v

test-delay: $(BUILD)/delay/test.out
	cd "$(BUILD)/delay" && $(VVP) -i test.out "+init_hex=$(ROM)" +check_eye +check_tinit $(VVP_ARGS)

test-delay-white: $(BUILD)/white-delay/test.out
	cd "$(BUILD)/white-delay" && $(VVP) -i test.out "+init_hex=$(ROM)" +check_eye +check_tinit $(VVP_ARGS)

test-video-fix: test-delay test-delay-white

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
		$(if $(filter white white-delay,$*),--white,--bars) $(if $(filter delay white-delay,$*),--delay) \
		$(if $(filter data-only data-timed,$*),--data-only) $(if $(filter data-timed,$*),--data-timing)

$(BUILD)/%/test.out: $(BUILD)/%/$(TOP).v $(RTL) $(MODELS) $(TB) $(TEST_INCLUDES) $(ROM_INCLUDE)/init_mem_table.vh
	$(IVERILOG) -g2012 -Wall -Wno-timescale -DFPGBC_WHITE -DFPGBC_FRAME -DPHY_GOWIN -DPHY_SUPERVISED \
		-I"$(ROM_INCLUDE)" -I"$(PHY)/TB" -I"$(PHY)/phy_supervisor/TB" -Itests \
		-s mipi_tx_TB -Pmipi_tx_TB.WHITE=$(if $(filter white white-delay,$*),1,0) \
		$(if $(filter data-only data-timed,$*),-DDATA_ONLY) $(if $(filter data-timed,$*),-DDATA_TIMING) \
		-o "$@" $(TB) $(MODELS) "$(BUILD)/$*/$(TOP).v" $(RTL)

synth: $(BUILD)/$(VARIANT)/$(TOP).json
route: $(BUILD)/$(VARIANT)/$(TOP)_routed.json
audit: route
	cd "$(ROOT)" && $(PYTHON) -m gateware.tests.review_white "$(BUILD)/$(VARIANT)" "$(REVIEW_VARIANT)"

fs: route
	cd "$(ROOT)" && $(PYTHON) -m gateware.tests.review_white "$(BUILD)/$(VARIANT)" \
		"$(REVIEW_VARIANT)" --output "$(BUILD)/$(VARIANT)/$(TOP).fs"

$(BUILD)/%/$(TOP).json: $(BUILD)/%/$(TOP).v $(BUILD)/%/$(TOP).ys $(ROM_INCLUDE)/init_mem_table.vh
	cd "$(@D)" && $(YOSYS) -Q -q -l synth.log -s $(TOP).ys

$(BUILD)/%/$(TOP).sdc: $(SDC)
	mkdir -p "$(@D)"
	cp "$<" "$@"

$(BUILD)/data-only/$(TOP).sdc: $(DATA_ONLY_SDC)
	mkdir -p "$(@D)"
	cp "$<" "$@"

$(BUILD)/data-timed/$(TOP).sdc: $(DATA_ONLY_SDC)
	mkdir -p "$(@D)"
	cp "$<" "$@"

$(BUILD)/%/$(TOP)_routed.json: $(BUILD)/%/$(TOP).json $(BUILD)/%/$(TOP).cst $(BUILD)/%/$(TOP).sdc
	cd "$(@D)" && $(NEXTPNR) --device GW2AR-LV18EQ144PC8/I7 \
		--vopt family=GW2A-18C --vopt cst=$(TOP).cst --vopt disable_gp_clock_routing \
		--sdc "$(TOP).sdc" --json "$(TOP).json" --write "$(@F)" --log route.log --report timing.json
