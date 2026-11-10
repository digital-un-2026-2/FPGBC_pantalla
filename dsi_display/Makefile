IVERILOG ?= iverilog
VVP ?= vvp
PYTHON ?= python
YOSYS ?= yosys
ROOT := $(abspath ..)
BUILD := $(ROOT)/build/dsi_display
RTL := $(wildcard src/*.v ../dsi_video_scheduler/src/*.v ../dsi_test_pattern/src/*.v ../dsi_long_packet_tx/src/*.v ../dsi_lp_packet_tx/src/*.v ../dsi_lane_packer/src/*.v ../dsi_hs_transport/src/*.v ../dphy_mode_ctrl/src/*.v ../dphy_hs_tx/src/*.v ../dsi_lpdt_bridge/src/*.v ../dphy_lpdt_tx/src/*.v ../dphy_gowin_tx/src/*.v)
MODELS := ../dphy_gowin_tx/TB/gowin_ideal_cells.v
.PHONY: check test test-link test-mailbox test-csr test-lp-board test-board-profile test-image check-structure
check:
	$(MAKE) -C ../dphy_gowin_tx declarations
	$(IVERILOG) -g2012 -Wall -s dsi_display_top -t null $(RTL) ../build/dphy_gowin_tx/gowin_declarations.v
	$(IVERILOG) -g2012 -Wall -s dsi_image_top -t null $(RTL) ../build/dphy_gowin_tx/gowin_declarations.v
test: test-link test-mailbox test-csr test-lp-board test-board-profile test-image check-structure
test-link:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -Wall -s display_link_TB -o $(BUILD)/link $(RTL) $(MODELS) TB/display_link_TB.v
	$(VVP) $(BUILD)/link
	$(IVERILOG) -g2012 -Wall -DGOWIN_MODEL_J=3 -s display_link_TB -o $(BUILD)/link_j3 $(RTL) $(MODELS) TB/display_link_TB.v
	$(VVP) $(BUILD)/link_j3
	$(IVERILOG) -g2012 -Wall -s display_link_TB -Pdisplay_link_TB.WIDTH=8 -Pdisplay_link_TB.HEIGHT=3 -o $(BUILD)/link_small $(RTL) $(MODELS) TB/display_link_TB.v
	$(VVP) $(BUILD)/link_small
test-mailbox:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -Wall -s display_mailbox_TB -o $(BUILD)/mailbox src/display_mailbox.v TB/display_mailbox_TB.v
	$(VVP) $(BUILD)/mailbox
test-csr:
	$(PYTHON) TB/generate_csr.py
	$(IVERILOG) -g2012 -Wall -I$(BUILD) -s display_csr_TB -o $(BUILD)/csr $(RTL) $(MODELS) $(BUILD)/display_csr.v TB/display_csr_TB.v
	$(VVP) $(BUILD)/csr
test-lp-board:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -Wall -s display_lp_board_TB -o $(BUILD)/lp_board $(RTL) $(MODELS) TB/display_lp_board_TB.v
	$(VVP) $(BUILD)/lp_board
test-board-profile:
	$(PYTHON) TB/test_board_profile.py
test-image:
	$(PYTHON) image/generate_assets.py --check
	$(PYTHON) image/generate_test_reference.py
	$(IVERILOG) -g2012 -Wall -I$(BUILD) -s display_image_TB -o $(BUILD)/image $(RTL) $(MODELS) TB/display_image_TB.v
	$(VVP) $(BUILD)/image
	$(IVERILOG) -g2012 -Wall -I$(BUILD) -DGOWIN_MODEL_J=3 -s display_image_TB -o $(BUILD)/image_j3 $(RTL) $(MODELS) TB/display_image_TB.v
	$(VVP) $(BUILD)/image_j3
	$(IVERILOG) -g2012 -Wall -I$(BUILD) -DIMAGE_BACKLIGHT_TEST -s display_image_TB -o $(BUILD)/image_backlight $(RTL) $(MODELS) TB/display_image_TB.v
	$(VVP) $(BUILD)/image_backlight
	$(IVERILOG) -g2012 -Wall -s display_image_raster_TB -o $(BUILD)/image_raster $(RTL) TB/display_image_raster_TB.v
	$(VVP) $(BUILD)/image_raster
check-structure:
	mkdir -p $(BUILD)
	$(MAKE) -C ../dphy_gowin_tx declarations
	$(PYTHON) TB/check_structure.py
