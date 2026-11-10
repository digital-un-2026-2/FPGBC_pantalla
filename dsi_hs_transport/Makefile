IVERILOG ?= iverilog
VVP ?= vvp
PYTHON ?= python
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BUILD := $(ROOT)/build/dsi_hs_transport
RTL := $(wildcard src/*.v)
LINK := $(wildcard ../dsi_lp_packet_tx/src/*.v ../dsi_long_packet_tx/src/*.v ../dsi_lane_packer/src/*.v ../dphy_mode_ctrl/src/*.v ../dsi_lpdt_bridge/src/*.v ../dphy_lpdt_tx/src/*.v)
.PHONY: check test test-unit test-link test-control check-structure waves
check:
	$(IVERILOG) -g2012 -Wall -s dsi_hs_transport -t null $(RTL)
test: test-unit test-link test-control
test-unit:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -Wall -s hs_transport_TB -o $(BUILD)/unit $(RTL) TB/hs_transport_TB.v
	$(VVP) $(BUILD)/unit
test-link:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -Wall -s hs_transport_link_TB -o $(BUILD)/link $(RTL) $(LINK) TB/hs_transport_link_TB.v
	$(VVP) $(BUILD)/link

test-control:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -Wall -s hs_transport_control_TB -o $(BUILD)/control $(RTL) TB/hs_transport_control_TB.v
	$(VVP) $(BUILD)/control

check-structure:
	mkdir -p $(BUILD)
	yosys -Q -T -p 'read_verilog $(RTL); hierarchy -top dsi_hs_transport; proc; opt; memory_dff; memory_collect; opt_clean; check -assert; select -assert-none t:$$dlatch; stat; write_json $(BUILD)/netlist.json' > $(BUILD)/yosys.log
	$(PYTHON) TB/check_structure.py $(BUILD)/netlist.json

waves:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -Wall -s hs_transport_link_TB -o $(BUILD)/link $(RTL) $(LINK) TB/hs_transport_link_TB.v
	$(VVP) $(BUILD)/link +vcd=$(BUILD)/link.vcd
