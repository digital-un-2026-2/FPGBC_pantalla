# Adaptado de o-arias/Digital-l: bin2bcd/bin2bcd_verilog/Makefile.
# Uso desde la raíz: make -C motor_lpdt test
TARGET ?= motor_lpdt
TB = TB/$(TARGET)_TB.v
# Añadir dependencias explícitas mediante OBJS="src/top.v src/otro.v".
ifeq ($(TARGET),motor_lpdt)
OBJS ?= src/motor_lpdt.v src/motor_control.v src/count.v src/comp.v src/reg_0.v src/mux.v
else ifeq ($(TARGET),count)
OBJS ?= src/count.v src/comp.v
else ifeq ($(TARGET),reg)
OBJS ?= src/reg_0.v
else
OBJS ?= src/$(TARGET).v
endif
BUILD_DIR = build
SIM_OUT = $(BUILD_DIR)/$(TARGET)_TB.out
VCD = $(BUILD_DIR)/$(TARGET)_TB.vcd
WAVE_CONFIG = $(wildcard waves/$(TARGET)_TB.gtkw)
IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
TEST_TARGETS = $(patsubst TB/%_TB.v,%,$(wildcard TB/*_TB.v))

.PHONY: sim test test-all wave clean

sim: test
	$(MAKE) wave TARGET=$(TARGET)

# Seleccionar el top evita ejecutar otros módulos como raíces de simulación.
test:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -DBENCH -s $(TARGET)_TB -o $(SIM_OUT) $(TB) $(OBJS)
	cd $(BUILD_DIR) && $(VVP) $(TARGET)_TB.out

test-all:
	@set -e; for target in $(TEST_TARGETS); do \
		$(MAKE) test TARGET=$$target; \
	done

wave:
	$(GTKWAVE) $(VCD) $(WAVE_CONFIG)

# Solo borra productos de los testbenches, no fuentes ni diagramas.
clean:
	rm -f -- $(BUILD_DIR)/*_TB.out $(BUILD_DIR)/*_TB.vcd
