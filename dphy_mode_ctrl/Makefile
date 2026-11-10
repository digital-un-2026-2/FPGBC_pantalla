IVERILOG ?= iverilog
VVP ?= vvp
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BUILD_DIR ?= $(ROOT)/build/dphy_mode_ctrl
MODE_RTL := $(wildcard $(ROOT)/dphy_mode_ctrl/src/*.v)
BRIDGE_RTL := $(wildcard $(ROOT)/dsi_lpdt_bridge/src/*.v)
LPDT_RTL := $(wildcard $(ROOT)/dphy_lpdt_tx/src/*.v)
PACKET_RTL := $(wildcard $(ROOT)/dsi_lp_packet_tx/src/*.v)
UNIT_TB := $(ROOT)/dphy_mode_ctrl/TB/dphy_mode_ctrl_TB.v
LINK_TB := $(ROOT)/dphy_mode_ctrl/TB/dphy_mode_link_TB.v
EDGES_TB := $(ROOT)/dphy_mode_ctrl/TB/dphy_mode_edges_TB.v
UNIT_SIM := $(BUILD_DIR)/dphy_mode_ctrl_TB.vvp
LINK_SIM := $(BUILD_DIR)/dphy_mode_link_TB.vvp
EDGES_SIM := $(BUILD_DIR)/dphy_mode_edges_TB.vvp

.PHONY: check test test-unit test-link test-edges waves

check:
	$(IVERILOG) -g2012 -Wall -s dphy_mode_ctrl -t null $(MODE_RTL)

$(UNIT_SIM): $(UNIT_TB) $(MODE_RTL)
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -s dphy_mode_ctrl_TB -o "$@" $(UNIT_TB) $(MODE_RTL)

$(LINK_SIM): $(LINK_TB) $(MODE_RTL) $(BRIDGE_RTL) $(LPDT_RTL) $(PACKET_RTL)
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -s dphy_mode_link_TB -o "$@" $(LINK_TB) $(MODE_RTL) $(BRIDGE_RTL) $(LPDT_RTL) $(PACKET_RTL)

$(EDGES_SIM): $(EDGES_TB) $(MODE_RTL)
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -s dphy_mode_edges_TB -o "$@" $(EDGES_TB) $(MODE_RTL)

test: test-unit test-link test-edges

test-unit: $(UNIT_SIM)
	$(VVP) "$(UNIT_SIM)"

test-link: $(LINK_SIM)
	$(VVP) "$(LINK_SIM)"

test-edges: $(EDGES_SIM)
	$(VVP) "$(EDGES_SIM)"

waves: $(UNIT_SIM) $(LINK_SIM) $(EDGES_SIM)
	$(VVP) "$(UNIT_SIM)" +vcd="$(BUILD_DIR)/dphy_mode_ctrl_TB.vcd"
	$(VVP) "$(LINK_SIM)" +vcd="$(BUILD_DIR)/dphy_mode_link_TB.vcd"
	$(VVP) "$(EDGES_SIM)" +vcd="$(BUILD_DIR)/dphy_mode_edges_TB.vcd"
