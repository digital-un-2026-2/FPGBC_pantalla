# CLOCK_DDR — reloj reenviado del PHY

[Datapath editable](docs/CLOCK_DDR.drawio) · [RTL](src/clock_ddr.v) ·
Dispositivo **GW2AR-LV18EQ144PC8/I7**.
`CLKDIV ÷2 + OSER4` produce un reloj nominal de 220 MHz. La sonda enrutó
simultáneamente D0, D1 y CLK, con y sin `IODELAY`. **La fase útil y los
tiempos de conducción en el panel siguen pendientes de validación.**

## Datapath y límite del bloque

`MIPI_PHY_bloques.pdf` define `CLK_HS`, `ENABLE` y `HS_CLK`. El diseño
aprobado resuelve ese `ENABLE` en el **OE del driver de reloj**, con el
`CLK_EN` generado por `PHY_CTRL`. `CLOCK_DDR` recibe `CLK_HS`, `ISO`
y `CLK_TOGGLE` (1 bit cada uno) y entrega `HS_CLK` (1 bit).
En la [integración](../docs/tabla_flancos.md), `CLK_TOGGLE` llega a `OSER4`
por dos registros en ↓`PCLK_110`, con borrado asíncrono a cero por
`RST_LOCAL`. Selecciona `0101` (alternar) o `0000` (HS-0). El OE queda
activo hasta terminar el último pulso y el HS-0 de cierre.
Así se evita reiniciar el divisor al armar,
cortar un pulso con una compuerta en `Q0` o usar `Q1` como única vía de
aborto. No hay otra FSM, reloj de byte local ni puerto nuevo en `MIPI_TX`.

- `CLK_HS` (220 MHz) alimenta por HCLK `CLKDIV.HCLKIN` y `OSER4.FCLK`.
  `CLKDIV.CLKOUT` es `PCLK_110` (110 MHz). `DIV_MODE="2"`, `CALIB=0`:
  `CALIB` no da el ajuste fino de fase.
- `OSER4` carga en ↑`PCLK_110`; con `D[3:0]=0101`, lanza `1,0,1,0`
  por `Q0`, en ambos flancos de `FCLK`. Cada nivel dura 1 UI = 2,273 ns;
  el periodo completo es 2 UI = 4,545 ns (**220 MHz**). `HWL="false"`,
  `LSREN="true"`, `GSREN="false"`; `TX0/TX1=0`, `Q1` sin usar.
- Único registro de usuario: `RST_HS[1:0]`, corre siempre en ↓`CLK_HS`.
  `ISO=1` lo aserta asíncronamente a `11`; con `ISO=0` desplaza ceros
  hasta `00` en dos ↓. La etapa final, `RST_LOCAL`, va a `OSER4.RESET`
  (activo alto, `Q0=0`) y, invertida, a `CLKDIV.RESETN` (activo bajo,
  `CLKOUT=0` en el modelo). Comprobar recuperación/remoción, incluida
  la liberación al caer `FCLK`, y la distribución del reset a ambas
  primitivas. `ISO` ya incorpora reset común y pérdida de lock según
  `PHY_CTRL`. La ruta a OE debe ser independiente de esta sincronización.
- Candidato de fase: `Q0 → IODELAY.DI → IODELAY.DO = HS_CLK`, por la
  ruta local de E/S. `SDTAP=0` para ajuste estático, `SETN=VALUE=0`,
  `DF` sin usar. `C_STATIC_DLY` es un valor a caracterizar; una variante
  directa `Q0 → HS_CLK` sirve de referencia y es la ruta por defecto
  (`USE_IODELAY=0`). `USE_IODELAY` y `STATIC_DELAY_TAPS` son parámetros
  de elaboración. La lógica no conmuta rutas ni cambia el retardo durante
  una ráfaga.

[DS226-2.7E][ds226], tabla 3-17, especifica 800 Mbit/s para `OSER4`
y 1200 Mbit/s para `OSER8` en GW2AR-18. La tabla no separa esos máximos
por grado; para este dispositivo **C8/I7**, 440 Mbit/s cabe en ambos,
pero supera los **400 Mbit/s** publicados para `ODDR` 2:1. Los límites
del gearbox no garantizan los del enlace completo.

| Flanco de lanzamiento, tras el llenado | ↑`FCLK` | ↓`FCLK` | ↑`FCLK` | ↓`FCLK` | ↑`FCLK` |
|---|---:|---:|---:|---:|---:|
| Tiempo nominal desde el primero | 0 UI | 1 UI | 2 UI | 3 UI | 4 UI |
| Bit de `OSER4` en `Q0` | `D0=1` | `D1=0` | `D2=1` | `D3=0` | `D0=1` de la siguiente carga |

## Referencia de flancos del diseño aislado

`B = Tbyte = 18,182 ns`. `↓z` es el ↓`CLK_BYTE` que muestrea la subida de
`HS_REQ`. Esta tabla documenta el control lógico de slots del PR #12.
Para las ventanas de la integración y el cambio de patrón, consultar la
[tabla del PHY Gowin](../docs/tabla_flancos.md). `Pᵢ` es ↑`CLK_BYTE` tras
`↓i`; `Fᵢ` lanza el primer bit del slot correspondiente en `OSER8.Q0`.

| Flanco o evento | Reloj reenviado | D0/D1 y condición de integración |
|---|---|---|
| `ISO=1`, incluso sin flancos | Reset asíncrono de divisor y `OSER4`; un flanco en tránsito puede llegar por `IODELAY`. | El OE de los tres pares HS se inhibe por `ISO` sin esperar reloj; se descarta la ráfaga. |
| `ISO↓`; dos ↓`CLK_HS`, luego primer ↑`PCLK_110` válido | Arranca el divisor, se carga `0101` y se llena el pipeline antes de usar `Q0`. | Rearme en reposo de `PHY_CTRL`; sin SoT ni OE HS. |
| ↑`CLK_BYTE` que entra a `ARM_CLK` | `CLK_ARM=1`, `CLK_EN=0`. `Q0` se estabiliza o ya alterna bajo aislamiento. | Preámbulo LP; verificar tiempo de asentamiento y primer flanco visible al habilitar OE. |
| `↓(z+1)`, primer slot ZERO | `CLK_EN=1`; la salida preparada se puede conducir. | `HS_EN=1`, modo ZERO. Medir el adelanto del reloj desde el primer flanco válido en el panel, con `T_CLK-PRE` y tiempos de transición aplicables. |
| `↓(z+T_ZERO+1)` → `Pᵢ` → `Fᵢ` | Flancos continuos, centrados en cada UI si se cierra la fase. | Se captura el `B8/B8` previo de `PHY_IF`, se carga en ↑ y se lanza LSB primero. Con `T_ZERO=1`, la captura queda a 1 B del primer ZERO, antes de sumar la latencia de datos. |
| `↓c` muestrea `HS_REQ↓`; `P_c`; `F_c…F_c+7 UI` | `CLK_ARM=CLK_EN=1`. | `WORD` captura CRC; sus ocho bits ocupan hasta `F_c+8 UI`. El ↑ siguiente selecciona TRAIL para el próximo slot, sin afectar el CRC. |
| `↓(c+1)…↓(c+T_TRAIL)` | El reloj continúa durante todos los slots. | El primer trail aparece en `F_c+8 UI`; cada carril repite el inverso de su último bit. |
| `↓off = ↓(c+1+T_TRAIL)` | `POST_CLK` conserva `CLK_EN`. | `HS_EN` cae y se captura OFF. La salida de OFF en `Q0` aún tarda `δ8`; el OE lógico por sí solo puede cortar CRC o trail. |
| ↑ posterior con ambas peticiones bajas; luego ↓ | Caen `CLK_EN` y `CLK_ARM`; el `OSER4` sigue alternando sin conducir. | Retirar OE una vez terminado el trail físico y satisfecha la retención de reloj; verificar el último pulso y la separación hasta el próximo LP. `ISO` tiene prioridad en cualquier instante. |

**Latencias distintas.** Lectura del [modelo funcional Gowin GW2A][model],
sin retardos físicos: `CLKDIV` entrega su primer ↑ en el segundo ↑ de
`CLK_HS` tras liberar `RST_LOCAL`; `OSER4` con `HWL=false` lanza el
primer bit de una carga tras 3–4 ciclos de `FCLK` según la relación de
captura. Para el arranque anterior, reservar en el modelo hasta
`2 T_HS + 2 T_HS + 4 T_HS = 36,36 ns` desde `ISO↓` para el primer
flanco, más `T_HS` para observar un periodo completo y el retardo de
salida. El mínimo lógico desde un rearme en SAFE hasta el primer
`CLK_EN` es 3 B (54,55 ns): SAFE→LP, LP→ARM_CLK, ARM_CLK→ZERO entre
los ↓ correspondientes. Esta comparación nominal deja ~13,64 ns antes
de descontar retardo de salida, recuperación y skew; falta acotarlos.
Las latencias observadas en simulación se detallan más abajo.

Por separado, [PR #14](../hs_serializer/README.md) obtuvo en el modelo
`δ8≈31,82–45,45 ns` desde la captura en ↓`CLK_BYTE` al bit 0 de cada
`OSER8`. Los ciclos enteros de latencia determinan el primer/último
slot y el OE; no suministran el retardo de medio UI.

**Criterio de cierre normal.** `t_CRC_fin = t(↓c) + δ8 + B`. Con el
OE de datos retirado en `↓off`, queda `T_TRAIL·B − δ8` de trail:
un slot corta CRC; cuatro dan ~27,27–40,91 ns frente a los ~69,09 ns
mínimos de trail *forward* citados en el PR #14. Siete darían
~81,82–95,45 ns en ese modelo, antes de márgenes. Hay que validar un
`T_TRAIL` compartido o alinear el cierre normal de OE con los slots
serializados. El par CLK debe seguir conduciendo hasta el final físico
del trail de **ambos** carriles más la retención de reloj que requiera
el enlace (`T_CLK-POST`). El ↑ inmediato después de `↓off` solo deja
½ B (9,09 ns) desde la retirada lógica de datos: no acredita esa
retención. El futuro OE debe garantizar también el pulso de salida
completo al retirar el reloj, y el no solape con LP; no deducirlo del
flanco de `CLK_BYTE` ni demorar el corte excepcional por `ISO`.

## Presupuesto de fase

Para cada carril `i` y cada polaridad de flanco, referir `Q0` de ambas
primitivas al **mismo** flanco de lanzamiento de `CLK_HS`, después de
comprobar la correspondencia de bits. Si `Δᵢ` es el desfase CLK–datos
medido o acotado en dichos Q0 sin `IODELAY`, e `Iᵢ` es el retardo
diferencial adicional hasta el panel (drivers, placa y cruce de umbral),
el objetivo es `Δᵢ + D_tap + Iᵢ ≈ 1,136 ns` para el flanco que
muestrea ese mismo bit. Comprobar que se asigna exactamente un flanco a
cada UI, también para el primer bit de SoT tras cada rearme. Un salto de
UI o un cambio de polaridad no se elimina tomando el resultado módulo UI
sin comprobar la secuencia. Un reloj cuadrado solo acredita frecuencia y duty.

| Término de error respecto al centro | Asignación propuesta, peor caso |
|---|---:|
| Residuo de centrado común en Q0, incluido el ajuste discreto | 0,150 ns |
| Diferencia `OSER4`–`OSER8` y skew relativo de HCLK residual sobre PVT/rearmes, en ambos flancos | 0,100 ns |
| Skew D0–D1 referido al punto medio de ambos carriles (½ dispersión) | 0,100 ns |
| Deriva de `IODELAY` sobre PVT y asimetría subida/bajada residual | 0,150 ns |
| Jitter relativo y reducción de la ventana por duty/anchura de UI | 0,100 ns |
| Driver, placa y umbral diferencial: error residual hasta el receptor | 0,150 ns |
| **Suma de errores asignados** | **0,750 ns** |
| **Distancia restante al borde ideal por lado** (`½UI − 0,750`) | **0,386 ns** |

Son objetivos de reparto, no cotas del fabricante ni valores observados.
La distancia restante debe cubrir setup y hold del receptor, incertidumbre
residual de medida y margen de integración; comprobar ambos lados por
separado sobre los límites reales de cada ojo. No hay datos para certificar
ese margen. Comprobar además setup/hold `PCLK_110`↔`FCLK`, los caminos
de medio ciclo del reset local y el traspaso ↓`CLK_BYTE`→↑`PCLK` de los
`OSER8`. La fase base común y la frecuencia 2:1/4:1 no acotan el skew.

[UG289][ug289], §§4.3.3 y 4.4.1, permite conectar `Q0` a `IODELAY`.
[DS226][ds226], tabla 2-4, da offset de 300–400 ps (350 ps típico) y
18 ps típicos por paso, 0…127: rango típico total ~0,35–2,64 ns, sin
cota publicada para el paso en esa tabla. Es ajuste de **retardo**, no
de adelanto. Buscar una intersección de taps válida para los dos carriles,
ambas polaridades y todos los rearmes/condiciones; si no existe, la ruta
no cierra. El tap 0 de la ruta con retardo tampoco equivale al bypass
físico. El modelo citado usa 25 ps por paso y tap 0 sin offset: sirve
para verificar conectividad, no para asignar taps ni certificar fase.

## Factibilidad de enrutado

UG115 y el cotejo de la base Apicula 0.32 (`GW2A-18C`, `eLQFP144P`)
confirman los siguientes pares del banco 1:

| Par | Pines P/N · sitio | Evidencia previa a la sonda de CLOCK_DDR |
|---|---|---|
| D0 | 117/116 · IOT40A/B · `X39Y0` | PR #14: `HCLK_OUT1 → FCLKA`; `CLK_BYTE` por GCLK a `CLK0/CLK1`. |
| D1 | 115/114 · IOT42A/B · `X41Y0` | PR #14: misma ruta, en el mismo enrutado que D0. |
| CLK | 113/112 · IOT48A/B · `X47Y0` | La base tiene IOLOGICA/B y `HCLK_OUT1`/`HCLK_OUT3 → FCLKA`. |

La sonda de `CLOCK_GEN` llevó `HCLK_IN0` al divisor superior
`X27Y0/CLKDIV_HCLK0_SECT0` y su salida a GCLK vía `THCLK0CLKDIV`.
La del PR #14 llevó ese mismo `HCLK_IN0` por sección 1 sin dividir a
`HCLK_OUT1` para D0/D1. La base expone ambos ramales y
`CLKDIV_0_CLKOUT → THCLK0CLKDIV`; la coexistencia es un candidato
topológico, no el resultado de unir los dos enrutados. La revisión del
[empaquetador nextpnr 0.11.1][packer] muestra soporte para absorber
`IODELAY` de salida en el IOLOGIC pilotado hacia un IOB.

### Resultado de la sonda de tres pares

```sh
pixi run --locked make -C phy/clock_ddr route
```

Con Yosys 0.69+, nextpnr 0.11.1 y Apicula 0.32 pasaron `route-direct` y
`route-delay`. En cada caso se usa `CLOCK_GEN` con dos instancias de
`HS_SERIALIZER`, más `CLOCK_DDR`. La PLL quedó en `X55Y45/PLL`.

| Red o salida | Ruta observada en ambas variantes |
|---|---|
| `CLK_HS` (220 MHz) | `BRPLL0CLK0 → GCLK → TBDHCLK0 → HCLK_IN0 → HCLK_OUT1 → FCLKA` de los **tres** pares. Una segunda rama usa `TBDHCLK1 → HCLK_IN2` para alimentar el divisor local; los registros de `RST_HS` usan GCLK. |
| `CLK_BYTE` (55 MHz) | `BRPLL0CLK3 → GCLK → GB10 → CLK0/CLK1` de D0 y D1. |
| `PCLK_110` (110 MHz) | `CLKDIV` en `X28Y0`, sección 0 en la variante directa y sección 1 con retardo; `THCLK1CLKDIV → GCLK → GB00 → CLK0` en `X47Y0`. |
| `HS_CLK` | `OSER4` en `X47Y0/IOLOGICAO`, modo `ODDRX2`, ruta local a `IOT48A/B`. En la variante con retardo, el IOLOGIC conserva `IODELAY=OUT` y `C_STATIC_DLY=32` como **valor de prueba**. |

[`verify_route.py`](tools/verify_route.py) comprueba los sumideros de
reloj, las tres salidas locales, el empaquetado del retardo y la
conexión de `ISO` al OEN del sumidero de reloj. La sonda usa `TLVDS_OBUF`
para D0/D1 y `TLVDS_TBUF` para CLK como cargas de P&R, sin un TOP del
PHY ni bitstream. Los informes quedan bajo `build/clock_ddr/direct/`
y `build/clock_ddr/delay/`.

**Límite temporal:** el reporte final indica que `CLK_HS` no tiene
caminos internos reportados y no aporta endpoints de E/S con los que
cerrar la relación `PCLK_110`/`FCLK`, la fase `Q0`–`Q0` o el OE.
El SDC fija periodos nominales. El enrutado no demuestra la recuperación
del reset a 220 MHz, setup/hold ni el margen del panel.

## Simulación funcional

```sh
pixi run --locked make -C phy/clock_ddr test
pixi run --locked make -C phy/clock_ddr test \
  PRIMITIVES=/ruta/absoluta/a/gw2a/prim_sim.v BUILD_DIR=../../build/clock_ddr_vendor
```

En el PR #16 el banco pasó con el [modelo local](TB/primitives_model.v) y
con el [modelo Gowin GW2A 1.9.14][model]. Verifica `/2`, alternancia a
una UI por nivel, y arranque desde `ISO↓` hasta el primer flanco de `Q0`
en **27,275–29,548 ns** para las tres liberaciones ensayadas, antes de
introducir los dos registros para `CLK_TOGGLE`. El banco aislado mantiene
`CLK_TOGGLE=1`; el cierre con cambio de patrón se verifica desde pads en
el banco de la integración. El banco aislado comprueba
un slot de adelanto, continuidad durante los slots que representan SoT,
1083 palabras, trail y retención, cierre normal del OE ideal en fase
baja, y aborto con `CLK_HS` detenido tanto en alto como en bajo, seguido
de rearme. Los 32 taps comprueban el desplazamiento de 800 ps del
modelo, sin calibración física. Los slots y el OE se modelan en el
banco: no se simula `PHY_CTRL`, la transmisión de CRC ni un driver real.
`test` corre sin ondas; `sim` vuelca FST y abre GTKWave; `wave` reabre
el último volcado.

## Pendiente para integrar

1. Cerrar setup/hold, recuperación/remoción de reset y fase de los
   tres serializadores. Medir CLK/D0/D1 diferencialmente, ambos flancos
   y tras rearme, con revisión de E/S y autorización separadas; elegir
   un tap solo si hay margen común en ambos carriles.
2. Alinear el OE normal de datos y reloj con la latencia real de los
   `OSER8`, el trail físico y `T_CLK-PRE`/`T_CLK-POST`; comprobar el
   primer y último pulso íntegros y la separación LP/HS. Llevar `ISO`
   al OE real por una ruta que no espere flancos.

[ds226]: https://cdn.gowinsemi.com.cn/DS226E.pdf
[ug289]: https://cdn.gowinsemi.com.cn/UG289E.pdf
[model]: https://github.com/BigPig-Bro/Gowin/blob/cb6df4cb3b74ebaffdb3df930dfd3073eca2ec00/Gowin_sim/gw2a/prim_sim.v
[packer]: https://github.com/YosysHQ/nextpnr/blob/nextpnr-0.11.1/himbaechel/uarch/gowin/pack_iologic.cc
