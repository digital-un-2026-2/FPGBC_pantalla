TARGET ?= secuenciador_control
TB = TB/$(TARGET)_TB.v
ifeq ($(TARGET),secuenciador_init)
OBJS ?= src/secuenciador_init.v src/secuenciador_control.v src/rom_descriptores.v src/rom_paquetes.v src/validador_descriptor.v ../motor_lpdt/src/count.v ../motor_lpdt/src/comp.v ../motor_lpdt/src/reg_0.v ../motor_lpdt/src/mux.v ../motor_lpdt/src/motor_lpdt.v ../motor_lpdt/src/motor_control.v
WAVE_EXT = fst
SIM_ARGS = -fst +waves
else
OBJS ?= src/$(TARGET).v
WAVE_EXT = vcd
SIM_ARGS =
endif
BUILD_DIR ?= ../build/secuenciador_init
WAVE_CONFIG = $(wildcard waves/$(TARGET)_TB.gtkw)
IVERILOG ?= iverilog
VVP ?= vvp
VVP_ARGS ?=
GTKWAVE ?= gtkwave

.PHONY: test test-all sim wave

test:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -DBENCH -s $(TARGET)_TB -o $(BUILD_DIR)/$(TARGET)_TB.out $(TB) $(OBJS)
	cd $(BUILD_DIR) && $(VVP) $(TARGET)_TB.out $(VVP_ARGS)

test-all:
	$(MAKE) test TARGET=secuenciador_control BUILD_DIR=$(BUILD_DIR)
	$(MAKE) test TARGET=secuenciador_init BUILD_DIR=$(BUILD_DIR)

sim: VVP_ARGS += $(SIM_ARGS)
sim: test
	$(MAKE) wave TARGET=$(TARGET) BUILD_DIR=$(BUILD_DIR)

wave:
	@test -f $(BUILD_DIR)/$(TARGET)_TB.$(WAVE_EXT) || { echo "Faltan ondas. Ejecuta make -C secuenciador_init sim TARGET=$(TARGET) desde la raiz."; exit 1; }
	$(GTKWAVE) $(BUILD_DIR)/$(TARGET)_TB.$(WAVE_EXT) $(WAVE_CONFIG)
