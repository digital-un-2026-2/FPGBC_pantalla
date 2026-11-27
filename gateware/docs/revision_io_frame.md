# Revisión previa a la prueba física del cuadro

**Candidato offline; no hay autorización de carga ni validación eléctrica.**
El hito sigue siendo ver barras estables en el LCD, no obtener un `.fs`.
Esta revisión no convierte simulación ni fusibles en medidas de placa.

## DSI y PHY HS

Números de **pin FPGA**, P/N:

| Par | LP, BANK0 | HS, BANK1 |
|---|---|---|
| D0 | 122 / 123 | 117 / 116 |
| D1 | 124 / 125 | 115 / 114 |
| CLK | 126 / 128 | 113 / 112 |

- BANK0 medido a 1,21 V: seis `TBUF/LVCMOS12`, DRIVE=8, slew FAST,
  pulls NONE. BANK1 medido a 2,52 V: tres `TLVDS_TBUF/LVDS25`, no GPIO
  LVCMOS25 conduciendo directamente 2,5 V hacia el panel.
- Red externa reportada: 100 Ω **por conductor** en la rama LP, unida
  a la rama HS directa. No equivale a 100 Ω entre P y N.
- En LPDT solo D0 conmuta. HS permanece apagado; D1 y CLK quedan LP11.
- En HS la rama LP aplica polarización 00 con OE independiente. Modos,
  aislamiento, drivers y retención del reloj son los del PHY integrado.
- `ISO` domina combinacionalmente los OEN activos bajos. El supervisor
  corta pads y backlight al perder referencia/byte/lock, incluso sin
  flancos de byte y con LOCK_RAW artificialmente alto.
- Perfil candidato: 55 MHz byte, 220 MHz CLK reenviado, 440 Mbit/s
  por carril. Reloj no continuo, orden LSB primero, D0 antes de D1
  al reintercalar bytes. No se afirma que sea el perfil original.
- Enrutado y auditoría deben confirmar PLL, rutas GCLK/HCLK/IOLOGIC,
  OEN físicos y el mapa mixto. No certifican swing, fase, jitter,
  setup/hold, impedancias o recepción D-PHY sobre la placa.

## Banco 5 y backlight

| Señal | Pin FPGA | Implementación candidata |
|---|---:|---|
| EN | 46 | OBUF, BANK5/LVCMOS33, activo alto |
| PWM | 47 | OBUF, BANK5/LVCMOS33, activo alto; 1 kHz al 50 % |

Se verifican pin/BEL/banco, estándar, pulls NONE y fusibles de ambos
OBUF y VCCIO=3,3 V **seleccionado por el empaquetador** para BANK5.
`TO=INV` es el atributo del perfil OBUF sin OEN de Apicula; no se usa
para invertir el dato EN/PWM ni confirma polaridad física del backlight.

**Pendiente que bloquea la carga:** confirmar la tensión VCCIO5 medida,
compatibilidad de niveles/umbrales, polaridad real de EN y PWM y estado
de los pines durante configuración. El pinout de la base de datos no
es una medida de VCCIO ni identifica el driver del backlight.

En RTL ambas salidas parten de 0. Se habilitan solo después de END
(incluido WAIT final de 7 ms); EN precede a PWM un ciclo de referencia.
EN queda alto entre ráfagas y PWM continúa alternando: PWM=0 durante
parte de su periodo no es un fallo. El corte por reset/ISO es asíncrono.

## Estado del panel antes del primer LP

- Se reporta alimentación estable, pero no se detecta en este TOP.
- PANEL_RST no es accesible; pin 120 es reset de FPGA, activo bajo,
  **no reset de LCD**. En este target es IBUF LVCMOS25 con pull-up en
  BANK1; verificar también su tensión real y comportamiento de arranque.
- El TOP supone que el panel ya está alimentado, con reset liberado
  y listo **antes del primer comando**. El POR de FPGA, la calificación
  del supervisor y los WAIT no demuestran ese estado del panel.
- No se añade Software Reset, BTA/ACK ni comandos para compensarlo.
- Antes de cargar, confirmar cómo se alcanza ese estado y si el panel
  admite repetir la ROM sin reset físico al recuperar el reloj.
- PULL_MODE=NONE solo rige tras configuración. Revisar los pulls y la
  conducción durante configuración y transición desde la imagen previa.

## Puerta de autorización de SRAM

1. Cerrar los puntos pendientes de VCCIO5/polaridades, arranque del LCD
   y revisión de E/S/PHY con el responsable.
2. Seleccionar el `.fs` nuevo de barras y verificar su SHA-256 contra
   `fpgbc_white.fs.review.json`, con `serialized_bitmap_roundtrip=true`.
3. Obtener **autorización separada de carga**. No se concede por aprobar
   el diseño ni por autorizar esta rama.
4. Revisar FT232RL y cableado JTAG del responsable (referencia previa:
   TXD:CTS:RTS:RXD), GND común y niveles. No confundir con UART 28/27.
5. Programar solo SRAM con el comando/cable confirmado; no escribir flash.
6. Registrar una de estas observaciones: **barras estables**, **solo
   retroiluminación**, **ninguna respuesta**; anotar también patrón,
   hash, alimentación, estado inicial y comportamiento al reiniciar.

**Estado actual de la prueba física: no ejecutada.** Ninguna de esas
tres observaciones ha sido obtenida en esta entrega.
