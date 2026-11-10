IVERILOG ?= iverilog
VVP ?= vvp
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BUILD_DIR ?= $(ROOT)/build/dsi_lp_packet_tx
RTL := $(wildcard $(ROOT)/dsi_lp_packet_tx/src/*.v)
TB := $(ROOT)/dsi_lp_packet_tx/TB/dsi_lp_packet_tx_TB.v
SIM := $(BUILD_DIR)/dsi_lp_packet_tx_TB.vvp

.PHONY: check test

check:
	$(IVERILOG) -g2012 -Wall -s dsi_lp_packet_tx -t null $(RTL)

test: $(TB) $(RTL)
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -s dsi_lp_packet_tx_TB -o "$(SIM)" $(TB) $(RTL)
	$(VVP) "$(SIM)"
