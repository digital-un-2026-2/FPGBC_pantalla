IVERILOG ?= iverilog
VVP ?= vvp
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BUILD_DIR ?= $(ROOT)/build/dsi_lane_packer
RTL := $(wildcard $(ROOT)/dsi_lane_packer/src/*.v)
PRODUCERS := $(wildcard $(ROOT)/dsi_lp_packet_tx/src/*.v) $(wildcard $(ROOT)/dsi_long_packet_tx/src/*.v)
TB := $(ROOT)/dsi_lane_packer/TB/dsi_lane_packer_TB.v
SIM := $(BUILD_DIR)/dsi_lane_packer_TB.vvp
EDGES_TB := $(ROOT)/dsi_lane_packer/TB/dsi_lane_packer_edges_TB.v
EDGES_SIM := $(BUILD_DIR)/dsi_lane_packer_edges_TB.vvp

.PHONY: check test test-link test-edges FORCE
check:
	$(IVERILOG) -g2012 -Wall -s dsi_lane_packer -t null $(RTL)

# Recompilar: Pixi y el sistema pueden usar versiones distintas de Icarus/VVP.
$(SIM): $(TB) $(RTL) $(PRODUCERS) FORCE
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -s dsi_lane_packer_TB -o "$@" $(TB) $(RTL) $(PRODUCERS)

$(EDGES_SIM): $(EDGES_TB) $(RTL) FORCE
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -s dsi_lane_packer_edges_TB -o "$@" $(EDGES_TB) $(RTL)

test: test-link test-edges

test-link: $(SIM)
	$(VVP) "$(SIM)"

test-edges: $(EDGES_SIM)
	$(VVP) "$(EDGES_SIM)"

FORCE:
