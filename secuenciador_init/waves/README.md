# Vistas GTKWave

Los `.gtkw` guardan selección y formato de señales, no las ondas:

- `secuenciador_control_TB.gtkw`: control y fallos con datapath/motor modelados.
- `secuenciador_init_TB.gtkw`: secuencia completa, ROM y motor reales; FSM en ASCII.

Desde la raíz:

```sh
pixi run make -C secuenciador_init sim TARGET=secuenciador_init
pixi run make -C secuenciador_init wave TARGET=secuenciador_init
```

`sim` regenera y abre; `wave` solo abre ondas existentes. La integrada usa FST
y control usa VCD, ambos en `build/secuenciador_init/`, fuera de Git.
