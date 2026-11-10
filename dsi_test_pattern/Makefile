IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys
PYTHON ?= python
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BUILD_DIR ?= $(ROOT)/build/dsi_test_pattern
RTL := $(wildcard $(ROOT)/dsi_test_pattern/src/*.v)
PACKET := $(wildcard $(ROOT)/dsi_long_packet_tx/src/*.v)
TB_DIR := $(ROOT)/dsi_test_pattern/TB

.PHONY: check test test-unit test-control test-link check-parameters check-structure
check:
	$(IVERILOG) -g2012 -Wall -s dsi_test_pattern -t null $(RTL)

test: test-unit test-control test-link check-parameters

# Recompilar siempre: Icarus del sistema y Pixi pueden tener versiones distintas.
test-unit:
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -s dsi_test_pattern_TB -o "$(BUILD_DIR)/unit.vvp" $(RTL) $(TB_DIR)/dsi_test_pattern_TB.v
	$(VVP) "$(BUILD_DIR)/unit.vvp"

test-control:
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -s test_pattern_control_TB -o "$(BUILD_DIR)/control.vvp" $(RTL) $(TB_DIR)/test_pattern_control_TB.v
	$(VVP) "$(BUILD_DIR)/control.vvp"

test-link:
	mkdir -p "$(BUILD_DIR)"
	$(IVERILOG) -g2012 -Wall -s test_pattern_link_TB -o "$(BUILD_DIR)/link.vvp" $(RTL) $(PACKET) $(TB_DIR)/test_pattern_link_TB.v
	$(VVP) "$(BUILD_DIR)/link.vvp"

check-parameters:
	$(PYTHON) $(TB_DIR)/check_parameters.py --iverilog "$(IVERILOG)" --yosys "$(YOSYS)"

check-structure:
	mkdir -p "$(BUILD_DIR)"
	$(YOSYS) -Q -T -p 'read_verilog $(RTL); hierarchy -check -top dsi_test_pattern; proc; flatten; opt; check -assert; select -assert-none t:$$dlatch; stat; write_json $(BUILD_DIR)/netlist.json' > "$(BUILD_DIR)/yosys.log"
	$(PYTHON) $(TB_DIR)/check_structure.py "$(BUILD_DIR)/netlist.json"
