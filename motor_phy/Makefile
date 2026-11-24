IVERILOG ?= iverilog
VVP ?= vvp
OBJS = src/motor_phy.v src/phy_control.v src/phy_mask.v src/phy_lanes.v \
       ../motor_lpdt/src/count.v ../motor_lpdt/src/comp.v ../motor_lpdt/src/mux.v

.PHONY: test test-all
test: test-all

test-all:
	mkdir -p build
	@set -e; for n in 1 2 4 7 8; do \
		$(IVERILOG) -g2012 -Wall -DBENCH -s motor_phy_TB \
			-Pmotor_phy_TB.N=$$n -o build/motor_phy_$$n.out TB/motor_phy_TB.v $(OBJS); \
		$(VVP) build/motor_phy_$$n.out; \
	done
