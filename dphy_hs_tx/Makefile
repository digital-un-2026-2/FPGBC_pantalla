IVERILOG ?= iverilog
VVP ?= vvp
PYTHON ?= python
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BUILD := $(ROOT)/build/dphy_hs_tx
RTL := $(wildcard src/*.v)
LINK := $(wildcard ../dsi_lp_packet_tx/src/*.v ../dsi_long_packet_tx/src/*.v ../dsi_lane_packer/src/*.v ../dsi_hs_transport/src/*.v ../dphy_mode_ctrl/src/*.v ../dsi_lpdt_bridge/src/*.v ../dphy_lpdt_tx/src/*.v)
FAULT_LINK := $(wildcard ../dsi_hs_transport/src/*.v ../dphy_mode_ctrl/src/*.v)
.PHONY: check test test-unit test-control test-link test-fault-link check-structure waves
check:
	$(IVERILOG) -g2012 -Wall -s dphy_hs_tx -t null $(RTL)
test: test-unit test-control test-link test-fault-link check-structure
test-unit:
	mkdir -p $(BUILD)
	$(PYTHON) TB/generate_vectors.py $(BUILD)/vectors.txt
	$(IVERILOG) -g2012 -Wall -s hs_phy_vectors_TB -o $(BUILD)/vectors $(RTL) TB/hs_phy_vectors_TB.v
	$(VVP) $(BUILD)/vectors +vectors=$(BUILD)/vectors.txt
test-control:
	mkdir -p $(BUILD)
	$(PYTHON) TB/generate_control_vectors.py $(BUILD)/control_vectors.txt
	$(IVERILOG) -g2012 -Wall -s hs_phy_control_TB -o $(BUILD)/control $(RTL) TB/hs_phy_control_TB.v
	$(VVP) $(BUILD)/control +vectors=$(BUILD)/control_vectors.txt
test-link:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -Wall -s hs_phy_link_TB -o $(BUILD)/link $(RTL) $(LINK) TB/hs_phy_link_TB.v
	$(VVP) $(BUILD)/link
test-fault-link:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -Wall -s hs_phy_fault_link_TB -o $(BUILD)/fault_link $(RTL) $(FAULT_LINK) TB/hs_phy_fault_link_TB.v
	$(VVP) $(BUILD)/fault_link
check-structure:
	mkdir -p $(BUILD)
	yosys -Q -T -p 'read_verilog $(RTL); hierarchy -top dphy_hs_tx; proc; flatten; opt; memory_map; opt; check -assert; select -assert-none t:$$dlatch; write_json $(BUILD)/flat.json' > $(BUILD)/yosys.log
	$(PYTHON) TB/check_structure.py $(BUILD)/flat.json
waves:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -Wall -s hs_phy_link_TB -o $(BUILD)/link $(RTL) $(LINK) TB/hs_phy_link_TB.v
	$(VVP) $(BUILD)/link +vcd=$(BUILD)/link.vcd
