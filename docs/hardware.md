# Hardware y precauciones

[Inicio](../README.md) · [Flujo de trabajo](flujo_de_trabajo.md) · [Arquitectura](arquitectura.md)

Este documento reúne los datos físicos y las precauciones. El procedimiento de
síntesis y carga está en el manual de trabajo. La confirmación del pinout por el
responsable no equivale a una validación eléctrica completa de D-PHY.

## Datos disponibles

| Elemento | Estado |
|---|---|
| Placa | FunnyPlaying FPGBC; revisión pendiente |
| FPGA | Gowin GW2AR-LV18EQ144PC8/I7, referencia confirmada por el responsable |
| Pantalla | LCD-49754 según el usuario; sufijo completo pendiente |
| Enlace | Un par CLK y dos pares de datos: D0 y D1 |
| Reloj de control | 40 MHz, periodo 25 ns; no es el reloj HS |
| RESET físico del panel | No accesible, confirmado por el usuario |
| Alimentación del panel | Secuencia resuelta y estable, según el usuario |

EarthLCD asocia LCD-49754-001 con JDI LT031MDZ4000 (720 × 720).
Es una referencia comercial, no identificación de todas las variantes ni
justificación para adoptar sus temporizaciones de vídeo.

Se prevé DCS Software Reset: requiere un receptor DSI operativo y no garantiza
recuperar cualquier fallo físico. Los seis conductores DSI no incluyen
alimentación, tierra ni retroiluminación.

## Conexiones de la integración de depuración

Referencia y pinout confirmados por el responsable para `gateware/platforms/fpgbc.py`:

| Recurso | Pin de FPGA | Declaración del target |
|---|---:|---|
| Reloj de control | 11 | 40 MHz, `LVCMOS33` |
| UART RX | 28 | Entrada de recepción en la FPGA, `LVCMOS33` |
| UART TX | 27 | Salida de transmisión de la FPGA, `LVCMOS33` |

UART es el enlace serie de depuración, no DSI. RX y TX se nombran desde la FPGA:
el transmisor del adaptador se conecta al receptor de la FPGA y viceversa,
con referencia de tierra común y niveles compatibles. No aplicar estos
estándares de 3,3 V a las ramas LP del panel.

La carga de configuración usa openFPGALoader con un FT232RL y la asignación
`TXD:CTS:RTS:RXD` indicada por el responsable. Esa asignación depende del
programador y cableado; no confundirla con los pines UART 28/27. La UART de
depuración se ha usado en `/dev/ttyACM2`, pero Linux puede asignar otro puerto.
Consultar los [comandos y comprobaciones](flujo_de_trabajo.md#5-cargar-temporalmente-en-la-fpga).

El target actual **no exporta `estado_D0` al panel**. Esto no resuelve por sí
solo el estado de los pines no utilizados: revisar su configuración y los bancos
conectados a la pantalla antes de cargar incluso una prueba interna.

## Mapa físico

**Los números son pines de FPGA, no contactos del conector de pantalla.**
Conectividad y resistencias aportadas por el usuario mediante seguimiento de
pistas. La función LP/HS está respaldada por Gowin IPUG948, figura 4-3; falta
validar la configuración concreta de E/S.

| Conductor | Rama GPIO/LP | Resistencia | Rama diferencial/HS |
|---|---:|---:|---:|
| CLK_N | 128 | 100 Ω | 112 |
| CLK_P | 126 | 100 Ω | 113 |
| D1_N | 125 | 100 Ω | 114 |
| D1_P | 124 | 100 Ω | 115 |
| D0_N | 123 | 100 Ω | 116 |
| D0_P | 122 | 100 Ω | 117 |

Cada fila tiene esta topología: doce pines de FPGA actúan sobre seis conductores.

```text
Pin GPIO/LP ── 100 Ω ──┬── Conductor de pantalla
Pin diferencial/HS ───┘
```

Los pads dorados y vías observados son posibles puntos de prueba, sin función
de fabricación confirmada. Las vías no convierten niveles ni protocolos.

## Alimentaciones medidas

| Banco | Pin VCCIO | Medición del usuario | Ramas |
|---|---:|---:|---|
| BANK0 | 127 | 1,30 V | GPIO/LP |
| BANK1 | 109 | 2,52 V | Diferenciales/HS |

UG229 identifica esos VCCIO para EQ144 y variantes; el pin 108 es VCC del núcleo.
Fecha, precisión y condiciones detalladas de medida no están registradas.
2,52 V es coherente con 2,5 V nominales, pero **1,30 V no certifica compatibilidad
con LVCMOS12**. Verificar límites de la FPGA exacta y precisión de medida.

## Drivers y seguridad

- VCCIO no determina por sí solo la tensión sobre el conductor. No aplicar
  3,3 V a LP ni asumir que 1,30 V está dentro de tolerancia para 1,2 V.
- Durante LPDT, el driver HS no debe conducir: se necesita controlar su
  habilitación real, no solo sus datos internos.
- En HS, las ramas GPIO pueden conducirse a cero para participar en la carga
  resistiva de referencia. No asumir alta impedancia sin validar la solución.
- Las seis resistencias de rama **no son una terminación entre P y N**.
  No añadir, retirar ni cambiar resistencias o alimentaciones por analogía.
- Una salida LVDS genérica no garantiza conformidad D-PHY. Antes de configurar
  estándares, corrientes o primitivas, comprobar FPGA exacta y red externa.
- No habilitar drivers simultáneamente sin analizar su interacción.
- Medir continuidad/resistencia solo con batería y USB desconectados.
- Para tensión, usar GND confirmado y pads de desacoplo identificados; evitar
  cortocircuitos entre patillas. Un multímetro no valida formas de onda HS.
- No programar flash ni ensayar en placa sin revisión de E/S y autorización.

## Referencias

- [FunnyPlaying FPGBC Kit](https://funnyplaying.com/products/fpgbc-kit).
- [EarthLCD: LCD-49754-001 / JDI LT031MDZ4000](https://earthlcd.com/products/earthlcd-3-1-720720).
- [Datasheet LT031MDZ4000](https://www.panoxdisplay.com/uploadfile/datasheet/LT031MDZ4000.pdf): confirmar variante antes de aplicar requisitos.
- [Gowin UG229](https://cdn.gowinsemi.com.cn/UG229E.pdf): tablas 3-4 a 3-6, encapsulados y alimentaciones.
- [Gowin DS226](https://cdn.gowinsemi.com.cn/DS226E.pdf): familia GW2AR.
- [Gowin IPUG948](https://cdn.gowinsemi.com.cn/IPUG948E.pdf): sección 4.2, figura 4-3, topología TLVDS con ramas de 100 Ω.
- [Gowin: soluciones MIPI](https://www.gowinsemi.com/en/market/white_papers/44).

Las notas e IP de fabricantes pueden tener restricciones propias; no convierten
una implementación particular en un requisito universal de MIPI.
