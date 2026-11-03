# Fuentes Verilog

[Interfaz y límites](../README.md)

| Módulo | Función |
|---|---|
| `fisical_layer.v` | Top físico LP combinacional: habilitaciones, dos IOBUF, cuatro TBUF auxiliares y seis TBUF HS siempre deshabilitados |
| `panel_init_top.v` | Conecta secuenciador, motor de ancho 4 e interfaz LP; sin CPU ni LiteX |

## Diseño de la integración

```text
clk, rst ───────────────→ secuenciador_init
                             │ solicitud, permiso_arranque, longitud, byte
                             ▼
                          motor_lpdt (ANCHO_LONGITUD=4)
                             │ estado_D0[1:0], sin registros adicionales
                             ▼
                          fisical_layer ──→ puertos LP/HS

secuenciador.rst_motor ──→ motor.rst y fisical_layer.rst_motor
secuenciador.preparar_lp → fisical_layer.preparar_lp
fisical_layer.lp_preparada → secuenciador.lp_preparada
motor.aceptado/ocupado/terminado/pos → secuenciador
```

Flujo: reset → estabilización del secuenciador → habilitar LP en reposo →
secuencia existente de 11 paquetes y esperas → LISTO. Fallo → `rst_motor=1` →
motor abortado y todos los drivers LP liberados. Las ramas HS nunca conducen.
El wrapper solo cablea los tres bloques: no añade FSM, registros ni tiempos.

El reset cubre un posedge y el negedge siguiente. El motor debe tener D0 en
LP-11 antes de que `preparar_lp` habilite los drivers. Se conservan los defaults
del secuenciador: estabilización de trabajo 20 ms y reposo inicial 200 µs, aún
no validados en placa, más los 285 ms de esperas DCS. Los parámetros se propagan
sin reducir esos valores en el diseño normal.

`panel_init_top` fija `liberar_d0=0`. Las lecturas de pads son observación local,
no respuestas decodificadas. En simulación se puede inyectar una liberación
forzando `w_liberar_d0`; no es una interfaz de control implementada. No hay BTA,
receptor LP ni recuperación automática del enlace.

## Buffers e integración posterior

Se instancian las primitivas Gowin `IOBUF(O, IO, I, OEN)` y `TBUF(O, I, OEN)`
con puertos nombrados y OEN activo a cero. Los modelos funcionales para Icarus
están exclusivamente en `TB/gowin_io_sim.v`; no añadirlos a fuentes de síntesis.

`hs_oen=111111` está conectado a seis TBUF reales en `fisical_layer`, no es
solo una salida informativa. `hs_pads[5:0]` son puertos de ramas, no un bus de
datos HS: orden conceptual CLK_N, CLK_P, D1_N, D1_P, D0_N, D0_P para índices
0…5. No se crea un transmisor diferencial.

No se proporcionan constraints ni se seleccionan estándares de E/S. Antes de
implementar en GW2AR-LV18EQ144PC8/I7, revisar legalidad de estas primitivas en
cada rama, que el flujo no elimine su deshabilitación y el estado efectivo de
todos los pads, pulls y terminaciones. Un buffer con OEN fijo no certifica su
estado durante configuración. No sintetizar/programar por inferencia de los
resultados de simulación.
