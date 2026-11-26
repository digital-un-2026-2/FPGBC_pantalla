# DPHY_PADS — diseño y factibilidad

[Datapath editable](docs/DPHY_PADS.drawio) · [RTL](src/dphy_pads.v)

Contrato: `MIPI_LCD/Docs/MIPI_PHY_bloques.pdf` en `digital_UN`. La vista
adapta `LP_DRIVERS` y `HS_DRIVERS` a los pads de la FPGBC. Las entradas
son `LP_P[2:0]`, `LP_N[2:0]`, `HS_D0`, `HS_D1`, `HS_CLK`,
`HS_EN`, `CLK_EN`, `ISO`, `LP_DAT_MODE[1:0]` y `LP_CLK_MODE[1:0]`.
Los dos modos reemplazan `LP_EN` en la interfaz del adaptador; el
[`PHY_CTRL` actual](../phy_ctrl/README.md) aún no los genera. `CLK_ARM`
y `SER_MODE[1:0]` tienen sus destinos en los bloques vecinos.
El adaptador es combinacional: recibe niveles serializados, modos y
habilitaciones, sin relojes internos, reset separado ni peticiones de
enlace.

| Modo del grupo | Rama LP con petición HS = 0 | Rama LP con petición HS = 1 | Diferencial si se pide HS |
|---|---|---|---|
| `00` (aislar), `11` (reservado) | Z | Z | Z |
| `01` (símbolo LP) | `LP_P/LP_N` | Z | Z |
| `10` (polarización HS) | `00` | `00` | `HS_D0/HS_D1` o `HS_CLK` |

La petición HS del grupo de datos es `HS_EN`; la de CLK es `CLK_EN`.
`ISO=1` prevalece sobre toda la tabla. En modo `10`, el TBUF ya puede
establecer `00` con el TLVDS todavía apagado. Mantener este modo hasta
después del corte físico del TLVDS del mismo grupo. La exclusión de
combinaciones incompatibles es combinacional y se define para entradas
estables; el supervisor debe secuenciar cambios con margen de
propagación. Usar `00` para un intervalo aislado entre modos `01` y
`10` cuando se requiera separación, y cambiar el modo con el OE HS bajo.

## Pines, primitivas y red externa

| Conductor | LP: `TBUF.O`, banco 0 | HS: `TLVDS_TBUF`, banco 1 |
|---|---:|---:|
| D0 P (`[0]`) | 122 | 117 (`O`, IOT40A) |
| D0 N (`[0]`) | 123 | 116 (`OB`, IOT40B) |
| D1 P (`[1]`) | 124 | 115 (`O`, IOT42A) |
| D1 N (`[1]`) | 125 | 114 (`OB`, IOT42B) |
| CLK P (`[2]`) | 126 | 113 (`O`, IOT48A) |
| CLK N (`[2]`) | 128 | 112 (`OB`, IOT48B) |

Los números son pines de la FPGA **GW2AR-LV18EQ144PC8/I7**. Cada `TBUF.I`
recibe el bit P o N correspondiente; cada `TLVDS_TBUF.I` recibe el serial
del par. Según [UG289] §§3.6.3 y 3.6.7, ambos `OEN` son activos en bajo:
`0` excita, `1` deja la salida en alta impedancia. `O` y `OB` se asignan
a P y N, respectivamente. En el modelo digital excitado son `I` y `¬I`;
esto no da las tensiones sobre el panel.

- **Banco 0:** VCCIO medido **1,21 V**, pin de alimentación 127 ([UG229],
  encapsulado EQ144P). `LVCMOS12` es de 1,2 V, rango 1,14–1,26 V, y
  admite 4/8 mA ([DS226], tablas 2-1 y 3-10). Para la sonda, partir del
  perfil LP explícito de 8 mA/FAST ya auditado; la selección de slew y
  la capacidad de hundimiento bajo carga siguen pendientes de
  [revisión eléctrica](../../docs/revision_io_lp.md).
- **Banco 1:** VCCIO medido **2,52 V**, pin de alimentación 109
  ([UG229]). [DS226], tabla 2-1, especifica `LVDS25` de salida como
  **TLVDS verdadero** con VCCIO nominal de 2,5 V; no se usa `LVDS25E` ni
  GPIO `LVCMOS25` para excitar HS. Los tres sitios diferenciales fueron
  usados en el [PR #16][pr16]. [UG289], tabla 3-12, no lista GW2AR-18
  para `MIPI_OBUF`.
- Solicitar `PULL_MODE=NONE` en los doce pads y comprobar su efecto en
  ambas mitades de cada par fusionado. No usar keeper ni terminación
  interna de entrada. [UG289] §3.3 describe pull-up débil durante
  configuración; `ISO` y los atributos de usuario se aplican una vez
  configurada la FPGA.

[Hardware de la placa](../../docs/hardware.md) reporta **100 Ω en serie con
cada rama LP** y la rama diferencial conectada directamente al mismo
conductor del panel. Esto coincide topológicamente con el **TX** de
[TN100], figura 3, al que remite [IPUG948] §4.2 para TLVDS. En LP,
el TLVDS queda en Z y los GPIO excitan el símbolo. En HS, los dos GPIO
del par **conducen a cero**: cada resistencia proporciona un camino hacia
un driver bajo y participa en la polarización/carga del diferencial.
Son dos ramas con referencia, no una resistencia de 100 Ω entre P y N
ni un pull-down débil. El ejemplo de TN100 usa 3,5 mA; DS226 enumera
opciones para LVDS25, pero el backend local de Apicula 0.32 impone
`DRIVE=0` en los atributos TLVDS. Ese código no acredita 3,5 mA ni
equivale a una lectura de corriente. Queda por confirmar la selección
efectiva, la red y la carga del panel, y medir modo común, swing y
transitorios antes de adoptar la adaptación. Los niveles LVDS de la
tabla 3-12 de DS226 se especifican con una carga diferencial de 100 Ω;
no se trasladan directamente a esta red.

## Tabla por par

`L(x)` = rama LP excitando `x={LP_P[i],LP_N[i]}`; `B` = rama LP
excitando `00` como **polarización HS**; `H(s)` = driver diferencial
excitado por `s`; `Z` = driver deshabilitado. Cada celda muestra
**rama LP / rama HS**. Salvo en aislamiento, `ISO=0`. La tabla de
referencia muestra la adaptación TN100 y, para las filas de arranque y
cierre de CLK, el caso de **reloj no continuo**; falta acordar el modo
y las ventanas del enlace.

| Fase | D0 (`i=0`) | D1 (`i=1`) | CLK (`i=2`) | Controles que debe presentar integración |
|---|---|---|---|---|
| Reposo LP | `L(11) / Z` | `L(11) / Z` | `L(11) / Z` | Ambos modos `01`, `HS_EN=CLK_EN=0`. |
| LPDT | `L(símbolo LPDT) / Z` | `L(11) / Z` | `L(11) / Z` | Mismos controles que en reposo. `PHY_IF` entrega los símbolos de `LP_TX` en D0, incluidos `10`, `01` y `00`. |
| Entrada LP01 / LP00 | `L(01→00) / Z` | `L(01→00) / Z` | `L(11) / Z` hasta el preámbulo propio; `L(01→00) / Z` en ese preámbulo | Modo `01` hasta completar el preámbulo del grupo. Hoy `PHY_IF` fija CLK en `11`; `CLK_ARM` solo prepara su ruta interna. |
| Polarización previa a HS | `B / Z` | `B / Z` | `B / Z` antes de activar CLK, en su ventana propia | Modo `10` y OE HS del grupo en 0 hasta que se asiente `B`. La secuencia de CLK puede adelantarse a la de datos. |
| Entrada HS / ráfaga | `B / H(HS_D0)` | `B / H(HS_D1)` | `B / H(HS_CLK)` | Ambos modos `10`, `HS_EN=CLK_EN=1`. |
| CRC y trail | `B / H(HS_D0)` hasta el fin físico | `B / H(HS_D1)` hasta el fin físico | `B / H(HS_CLK)` | Mantener ambos modos `10` y sus OE activos. El serializador transmite el CRC del último WORD y luego el patrón de TRAIL. |
| Retención de CLK | `B / Z` al retirar HS, luego conmutación y `L(11) / Z` | `B / Z` al retirar HS, luego conmutación y `L(11) / Z` | `B / H(HS_CLK)` hasta completar la retención y el último pulso; después corte y retorno LP | `HS_EN=0`; datos pueden pasar de `10` a `00` y `01`. CLK conserva modo `10` y `CLK_EN=1` hasta su cierre. |
| Aislamiento | `Z / Z` | `Z / Z` | `Z / Z` | `ISO=1` domina los doce pads, independientemente de los otros controles. Z describe los drivers; no fija el potencial del nodo del panel. |

El `LP_EN` común deshabilita los tres pares al entrar en HS: no
establece la polarización TN100 ni permite devolver los datos a LP11
con el valor LP actual de CLK en `11`. Tampoco basta con cambiar
`LP_P/N` a `00` si los TBUF están en Z. Los modos separados del
adaptador resuelven esa selección; integración debe producirlos y
definir la fuente del preámbulo LP de CLK.

## Condiciones para `PHY_CTRL` e integración

- **Aborto:** `ISO` debe alcanzar los OEN físicos de LP, datos HS y CLK
  HS por rutas combinacionales aun si se detienen `CLK_BYTE` y `CLK_HS`.
  Puede interrumpir una palabra, el trail o un pulso; se descarta la
  ráfaga. `PHY_CTRL` debe mantener los OE en estado seguro al liberar
  `ISO`, hasta completar su secuencia de rearme. Auditar el retardo de
  propagación y la distribución de `ISO`; con `CLOCK_DDR` también hay
  reset asíncrono en la ruta de datos del reloj y puede haber un flanco
  en tránsito antes del corte. No usar `Q1` del serializador como única
  vía de aislamiento.
- **Entrada y traspaso normal:** asegurar símbolos LP estables antes de
  habilitar los pads, no solapar excitación LP incompatible con HS y,
  si se adopta TN100, establecer `B` para el par antes de conducir HS.
  Cerrar el preámbulo, fase y primer pulso de CLK; comprobar el adelanto
  `T_CLK-PRE` y, si el modo lo exige, la secuencia LP y HS-zero del reloj.
  `CLK_ARM` no equivale a conducción en el panel.
- **Datos:** mantener `HS_EN` efectivo hasta transmitir el último bit
  del CRC y completar todo el trail en **ambos** carriles. El OFF del
  slot está antes del OFF serializado: según
  [`CLOCK_DDR`](../clock_ddr/README.md#tabla-de-flancos-arranque-ráfaga-y-cierre),
  el margen de trail del OE actual es `T_TRAIL·Tbyte − δ8`,
  donde `δ8` es el retardo captura→bit 0.
  El modelo da `δ8≈31,82–45,45 ns`: con un slot se corta el CRC, y
  cuatro slots dejan solo ~27,27–40,91 ns de trail. Son resultados del
  modelo, no tiempos de los pads. Integración debe alinear el OE con
  la serialización o cerrar una configuración común de tiempos que
  satisfaga el trail, la transición de salida y la línea.
- **Reloj:** conservar `CLK_EN` durante el trail físico de datos y
  hasta cumplir `T_CLK-POST`; retirarlo en una ventana de fase segura,
  incluyendo el retardo hasta el OEN, para evitar recortar el último
  pulso. El ↑ de byte inmediato deja solo ½ ciclo de byte desde el
  corte lógico de datos y no acredita ni la retención ni la fase.
  Restaurar LP con tiempo de separación suficiente. El adaptador toma
  OE de datos y reloj independientes y no cuenta slots, inspecciona el
  serial ni aplica compuertas a los relojes internos.

## Pruebas offline

```sh
pixi run --locked make -C phy/dphy_pads test
pixi run --locked make -C phy/dphy_pads test \
  PRIMITIVES=/ruta/a/gw2a/prim_sim.v BUILD_DIR=../../build/dphy_pads_vendor
pixi run --locked make -C phy/dphy_pads route
pixi run --locked make -C phy/dphy_pads -k audit
```

El banco verifica los doce pads en todas las combinaciones digitales
de modos y símbolos, incluido `ISO` con las salidas de los vecinos
congeladas y sin flancos de byte ni de serialización. Prueba también
el retorno a LP11 de D0/D1 con CLK diferencial. Pasa con el modelo
local y con el [modelo Gowin GW2A][sim]. `sim` y `wave` usan el mismo
banco y una traza FST.

La sonda usa `CLOCK_GEN`, dos `HS_SERIALIZER`, `CLOCK_DDR` y
`DPHY_PADS`, con estímulo dinámico. El PR #16 usaba `TLVDS_OBUF` para
datos; aquí los tres pares usan `TLVDS_TBUF` simultáneamente. La revisión
de P&R comprueba los 12 pines, la fusión A/B, los cuatro OEN y su
selección combinacional por `ISO`, los seis TBUF LP y las rutas locales
`OSER8/OSER4 → IOB` con HCLK/GCLK dedicados. Corre con CLK directo y
con `IODELAY=32` como variante de prueba, sin elegir aún un tap del
panel.

La auditoría `audit` captura atributos efectivos de los dos bancos y
de ambas mitades A/B en Apicula, conserva el registro de pads usados
y se detiene antes de serializar. Contrasta los fusibles seleccionados,
incluidos `LVDS_OUT=ON`, `TRIMUX_PADDT=SIG` y `TO=SIG` en HS. Reportes:
`build/dphy_pads/{direct,delay}/fuse_review.json`. Es una comprobación
distinta de la [auditoría LP](../../docs/revision_io_lp.md), que exige
`LVDS_OUT=OFF` para la rama HS aislada.

**Resultado:** con nextpnr 0.11.1 pasan las dos variantes de P&R. En
Apicula 0.32 los atributos de pulls, fusión y OEN dinámico se conservan,
pero **`audit` falla en las dos variantes**. El codificador usa como
fallback `BANK_VCCIO=1.2` para el banco 1, que solo tiene salidas
TLVDS en la sonda, y lo aplica a sus seis pads HS. En LP codifica
`DRIVE=UNKNOWN` a pesar del `DRIVE=8` del CST: la comprobación de
tipo LVDS reutiliza el modo del último buffer de la primera pasada
en lugar del modo del IOB actual. La lectura de estos atributos no
cambia el VCCIO físico medido de 2,52 V. Una copia temporal del
codificador que seleccionó el banco de salida según `LVDS25` y leyó
el modo del IOB actual pasó las dos auditorías en memoria; no se usa
como empaquetador del proyecto. Antes de habilitar el perfil en placa
queda por aprobar un flujo que conserve esos atributos y validar la
red eléctricamente.

P&R y simulación verifican conectividad y selección digital. Para
integración quedan la secuencia LP de CLK, el adelanto y el cierre
normal de los OE por grupo; para placa quedan la red, la corriente,
el modo común, los niveles y la fase.

[UG229]: https://cdn.gowinsemi.com.cn/UG229E.pdf
[UG289]: https://cdn.gowinsemi.com.cn/UG289E.pdf
[DS226]: https://cdn.gowinsemi.com.cn/DS226E.pdf
[TN100]: https://cdn.gowinsemi.com.cn/TN100E.pdf
[IPUG948]: https://cdn.gowinsemi.com.cn/IPUG948E.pdf
[pr16]: https://github.com/digital-un-2026-2/FPGBC_pantalla/pull/16
[sim]: https://github.com/BigPig-Bro/Gowin/blob/cb6df4cb3b74ebaffdb3df930dfd3073eca2ec00/Gowin_sim/gw2a/prim_sim.v
