TARGET ?= fisical_layer
BUILD_DIR ?= ../build/fisical_layer
IVERILOG ?= iverilog
VVP ?= vvp
VVP_ARGS ?=
GTKWAVE ?= gtkwave
IO_MODELS ?= TB/gowin_io_sim.v

ifeq ($(TARGET),panel_init_top)
OBJS ?= src/panel_init_top.v src/fisical_layer.v \
  ../secuenciador_init/src/secuenciador_init.v \
  ../secuenciador_init/src/secuenciador_control.v \
  ../secuenciador_init/src/rom_descriptores.v \
  ../secuenciador_init/src/rom_paquetes.v \
  ../secuenciador_init/src/validador_descriptor.v \
  ../motor_lpdt/src/motor_lpdt.v ../motor_lpdt/src/motor_control.v \
  ../motor_lpdt/src/count.v ../motor_lpdt/src/comp.v \
  ../motor_lpdt/src/reg_0.v ../motor_lpdt/src/mux.v
else
OBJS ?= src/fisical_layer.v
endif

.PHONY: test test-all sim wave

test:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -DBENCH -s $(TARGET)_TB -o $(BUILD_DIR)/$(TARGET)_TB.out TB/$(TARGET)_TB.v $(OBJS) $(IO_MODELS)
	cd $(BUILD_DIR) && $(VVP) $(TARGET)_TB.out $(VVP_ARGS)

test-all:
	$(MAKE) test TARGET=fisical_layer BUILD_DIR=$(BUILD_DIR)
	$(MAKE) test TARGET=panel_init_top BUILD_DIR=$(BUILD_DIR)

sim: VVP_ARGS += -fst +waves
sim: test
	$(MAKE) wave TARGET=$(TARGET) BUILD_DIR=$(BUILD_DIR)

wave:
	@test -f $(BUILD_DIR)/$(TARGET)_TB.fst || { echo "Faltan ondas: ejecutar sim para este TARGET."; exit 1; }
	$(GTKWAVE) $(BUILD_DIR)/$(TARGET)_TB.fst
