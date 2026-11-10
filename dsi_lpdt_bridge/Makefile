IVERILOG ?= iverilog
VVP ?= vvp
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BUILD_DIR ?= $(ROOT)/build/dsi_lpdt_bridge
BRIDGE_RTL := $(wildcard $(ROOT)/dsi_lpdt_bridge/src/*.v)
LPDT_RTL := $(wildcard $(ROOT)/dphy_lpdt_tx/src/*.v)
PACKET_RTL := $(wildcard $(ROOT)/dsi_lp_packet_tx/src/*.v)
TB := $(ROOT)/dsi_lpdt_bridge/TB/dsi_lpdt_bridge_TB.v
SIM := $(BUILD_DIR)/dsi_lpdt_bridge_TB.vvp

.PHONY: check test waves

check:
	$(IVERILOG) -g2012 -Wall -s dsi_lpdt_bridge -t null $(BRIDGE_RTL) $(LPDT_RTL)

$(SIM): $(TB) $(BRIDGE_RTL) $(LPDT_RTL) $(PACKET_RTL)
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -s dsi_lpdt_bridge_TB -o "$@" $(TB) $(BRIDGE_RTL) $(LPDT_RTL) $(PACKET_RTL)

test: $(SIM)
	$(VVP) "$(SIM)"

waves: $(SIM)
	$(VVP) "$(SIM)" +vcd="$(BUILD_DIR)/dsi_lpdt_bridge_TB.vcd"
