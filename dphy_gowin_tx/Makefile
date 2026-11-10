IVERILOG ?= iverilog
VVP ?= vvp
PYTHON ?= python
YOSYS ?= yosys
GOWIN_LIB ?= /usr/share/yosys/gowin
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BUILD := $(ROOT)/build/dphy_gowin_tx
RTL := $(wildcard src/*.v)
LINK := $(wildcard ../dphy_hs_tx/src/*.v ../dsi_lp_packet_tx/src/*.v ../dsi_long_packet_tx/src/*.v ../dsi_lane_packer/src/*.v ../dsi_hs_transport/src/*.v ../dphy_mode_ctrl/src/*.v ../dsi_lpdt_bridge/src/*.v ../dphy_lpdt_tx/src/*.v)
.PHONY: check test test-unit test-link test-fault-link check-structure check-gowin declarations
check: declarations
	$(IVERILOG) -g2012 -Wall -s dphy_gowin_tx -t null $(RTL) $(BUILD)/gowin_declarations.v
test: test-unit test-link test-fault-link check-structure check-gowin
test-unit:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -Wall -s gowin_tx_TB -o $(BUILD)/unit $(RTL) TB/gowin_ideal_cells.v TB/gowin_tx_TB.v
	$(VVP) $(BUILD)/unit
	$(IVERILOG) -g2012 -Wall -DGOWIN_MODEL_J=3 -s gowin_tx_TB -o $(BUILD)/unit_j3 $(RTL) TB/gowin_ideal_cells.v TB/gowin_tx_TB.v
	$(VVP) $(BUILD)/unit_j3
test-link:
	mkdir -p $(BUILD)
	$(PYTHON) TB/generate_link.py $(BUILD)/gowin_link_TB.v
	$(IVERILOG) -g2012 -Wall -s gowin_link_TB -o $(BUILD)/link $(RTL) $(LINK) TB/gowin_ideal_cells.v $(BUILD)/gowin_link_TB.v
	$(VVP) $(BUILD)/link
	$(IVERILOG) -g2012 -Wall -DGOWIN_MODEL_J=3 -s gowin_link_TB -o $(BUILD)/link_j3 $(RTL) $(LINK) TB/gowin_ideal_cells.v $(BUILD)/gowin_link_TB.v
	$(VVP) $(BUILD)/link_j3
test-fault-link:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -Wall -s gowin_fault_link_TB -o $(BUILD)/fault_link $(RTL) $(LINK) TB/gowin_ideal_cells.v TB/gowin_fault_link_TB.v
	$(VVP) $(BUILD)/fault_link
	$(IVERILOG) -g2012 -Wall -DGOWIN_MODEL_J=3 -s gowin_fault_link_TB -o $(BUILD)/fault_link_j3 $(RTL) $(LINK) TB/gowin_ideal_cells.v TB/gowin_fault_link_TB.v
	$(VVP) $(BUILD)/fault_link_j3
declarations:
	mkdir -p $(BUILD)
	$(PYTHON) TB/vendor_declarations.py $(GOWIN_LIB) $(BUILD)/gowin_declarations.v
check-structure: declarations
	mkdir -p $(BUILD)
	$(YOSYS) -Q -T -p 'read_verilog -lib $(BUILD)/gowin_declarations.v; read_verilog $(RTL); chparam -set PROFILE_OK 1 dphy_gowin_tx; hierarchy -check -top dphy_gowin_tx; proc; flatten; opt; check -assert; select -assert-none t:$$dlatch; write_json $(BUILD)/flat.json' > $(BUILD)/yosys.log
	$(PYTHON) TB/check_structure.py $(BUILD)/flat.json

	$(PYTHON) TB/generate_structure.py $(BUILD)/structure_link.v
	$(YOSYS) -Q -T -p 'read_verilog -lib $(BUILD)/gowin_declarations.v; read_verilog $(RTL) ../dphy_hs_tx/src/*.v ../dphy_mode_ctrl/src/*.v ../dsi_hs_transport/src/*.v $(BUILD)/structure_link.v; hierarchy -check -top gowin_link_structure; proc; flatten; opt; scc -expect 0' > $(BUILD)/scc.log
check-gowin:
	mkdir -p $(BUILD)
	$(YOSYS) -Q -T -p 'read_verilog $(RTL); chparam -set PROFILE_OK 1 dphy_gowin_tx; synth_gowin -family gw2a -top dphy_gowin_tx -json $(BUILD)/gowin.json' > $(BUILD)/gowin-synth.log
