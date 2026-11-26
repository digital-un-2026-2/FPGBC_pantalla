# HS_SERIALIZER — serializador DDR de un carril

[Datapath editable](docs/HS_SERIALIZER.drawio) · [RTL](src/hs_serializer.v).
`SERIALIZER_D0` y `SERIALIZER_D1` instancian el mismo módulo, con
`HS_BYTE0` y `HS_BYTE1` respectivamente. `CLK_BYTE` y `CLK_HS` vienen de
[`CLOCK_GEN`](../clock_gen/README.md); `SER_MODE[1:0]` e `ISO`, de
[`PHY_CTRL`](../phy_ctrl/README.md). El registro de
[`PHY_IF`](../../mipi_tx/phy_if/README.md) y el del serializador actualizan
en ↓; el serializador lee el valor anterior. El `Q0` de `OSER8` va al
driver externo por la ruta local de E/S.

| `SER_MODE` | `SLOT_Q[7:0]` capturado en ↓ | `LAST_BIT` |
|---|---|---|
| `00` OFF | `00` de relleno; OE externo | Borra |
| `01` ZERO | `00`, nivel diferencial HS-0 antes del SoT | Borra |
| `10` WORD | `HS_BYTE[7:0]` | Guarda `HS_BYTE[7]` |
| `11` TRAIL | Ocho repeticiones de `~LAST_BIT` | Conserva |

El [procedimiento de conformidad D-PHY][dphy], pruebas 1.3.3 y 1.3.13,
describe HS-0 antes del SoT y el nivel diferencial contrario al último
bit durante el trail. El patrón se calcula por carril: con CRC `EE/7E`
(D0/D1), el trail es `0/1`. El flanco ↑ que cambia el modo a `TRAIL` no
afecta el CRC ya capturado. `RST_BYTE || ISO` aserta el reset local del
registro y de `OSER8` de forma asíncrona; descarta la ráfaga aunque no
haya flancos. `PHY_CTRL` gobierna el corte físico y el rearme; al liberar
el reset hay que comprobar que ambos IOLOGIC arrancan en la misma fase.

## Tabla de flancos para integración

Perfil candidato del GW2AR-LV18EQ144PC8/I7: `PCLK=55 MHz`, `FCLK=220 MHz`,
`UI≈2,273 ns`, ocho UI por byte. `Pᵢ` es el **↑PCLK después de ↓i**.
`Fᵢ` es el ↑FCLK que lanza `b0` en `Q0` tras la latencia interna. Los
bits se emiten en `Fᵢ + j·UI` para `j=0…7`, de `D0` a `D7` de la
primitiva (↑ para `j` par, ↓ para impar).

| Flanco | `PHY_IF` publica después de ↓ (D0/D1) | Slot capturado en ↓ | Carga | Q0 desde `Fᵢ` |
|---|---|---|---|---|
| `↓−1` | SoT `B8/B8` | `ZERO` | `P₋₁` | HS-0 |
| `↓0` | W0 `3E/70` | `WORD`: SoT anterior | `P₀` | `00011101`/`00011101` |
| `↓1` | W1 `08/13` | `WORD`: W0 | `P₁` | `01111100`/`00001110`, contiguo a SoT |
| `↓2…↓1081` | W2…W1081 | `WORD`: W1…W1080 | `Pᵢ` | `b0…b7` de cada byte |
| `↓1082` | W1082, CRC bajo/alto | `WORD`: W1081 | `P₁₀₈₂` | Últimos píxeles, `b0…b7` |
| `↓1083` | `00/00` sin dato; `HS_REQ` bajo | `WORD`: CRC; guarda `b7` por carril | `P₁₀₈₃` | Ocho bits del CRC |
| `↓1084…` | Sin dato | `TRAIL`, sin leer otro byte del packer | `Pᵢ` | Nivel `~LAST_BIT`, desde el UI siguiente al CRC |
| `↓(1084 + T_TRAIL)` | Sin dato | `OFF` | `Pᵢ` | Relleno cero tras la latencia |

[UG289 §4.3.4][ug289] describe la relación 4:1 y el reset de `OSER8`.
El [modelo funcional de Gowin para GW2A][prim-sim] carga en ↑PCLK. Con
`HWL=false`, el primer bit sale 5–8 ciclos de `FCLK` después de `Pᵢ`
en el modelo con subidas coincidentes. Sumando el medio ciclo nominal
entre ↓i y `Pᵢ`, la latencia `δ` de captura a `b0` es ≈31,82–45,45 ns.
El periodo de salida entre slots sigue siendo `Tbyte`: el CRC termina
exactamente cuando empieza trail, sin un byte adicional de datos.

**Ventana de OE:** con el cierre actual en `↓(1084 + T_TRAIL)` el
trail físico ideal sería `T_TRAIL × Tbyte − δ`. A 55 MHz, un slot
truncaría el CRC, y cuatro dejan ≈27,27–40,91 ns de trail, menos que los
≈69,09 ns mínimos de D-PHY forward (`max(8 UI, 60 ns + 4 UI)`). Siete
slots cubrirían el ejemplo nominal si se conserva ese cierre. La
integración debe fijar el parámetro compartido o alinear el OE normal
con la ventana serializada tras validar la latencia y los márgenes de
reloj y retorno LP. `ISO` sigue siendo un corte inmediato.

## Simulación

```sh
pixi run --locked make -C phy/hs_serializer test
pixi run --locked make -C phy/hs_serializer sim
pixi run --locked make -C phy/hs_serializer wave
```

El [banco](TB/hs_serializer_TB.v) reconstruye ambos carriles desde Q0
flanco a flanco: cinco ráfagas, cada una de SoT más 1083 palabras. Prueba
arranque y ráfagas consecutivas, `ZERO`, CRC `EE/7E` y `7E/EE`, 1 y 4
slots de trail, ausencia de bytes extra y rearme tras `ISO` o `RST_BYTE`
en mitad de una palabra con los relojes detenidos. Alternar los CRC
inyectados comprueba las dos polaridades de trail por carril. El banco
comprueba su transporte; el cálculo de CRC corresponde al packer.

El [modelo local](TB/oser8_model.v) solo se compila para simulación.
El mismo banco pasó con el [modelo funcional de Gowin][prim-sim] (GW2A,
revisión `1.9.14` del archivo) en las cuatro fases de liberación de reset:
δ de **31 822, 36 368, 40 914 y 45 460 ps** con `UI=2273 ps` en el banco.
Para repetir el contraste con una copia de la biblioteca:

```sh
pixi run --locked make -C phy/hs_serializer test \
  OSER_MODEL=/ruta/absoluta/a/gw2a/prim_sim.v BUILD_DIR=../../build/hs_serializer_vendor
```

`test` no genera ondas. `sim` usa el mismo banco y guarda el FST en
`build/hs_serializer/`; `wave` abre ese archivo.

## Sonda aislada de síntesis y enrutado

```sh
pixi run --locked make -C phy/hs_serializer route
```

La sonda usa `CLOCK_GEN`, dos instancias del RTL y dos `TLVDS_OBUF` como
sumideros de P&R. Yosys 0.69+ y nextpnr 0.11.1 colocaron ambos `OSER8`
en modo `ODDRX4`, con el sitio auxiliar `IOLOGICBO` y el camino de datos
local hacia cada par diferencial. No produce bitstream.

| Carril | Pines P/N y sitio | `PCLK` observado | `FCLK` observado |
|---|---|---|---|
| D0 | 117/116 · IOT40A/B · `X39Y0` | `GB00 → CLK0` y `CLK1` | `HCLK_OUT1 → FCLKA` |
| D1 | 115/114 · IOT42A/B · `X41Y0` | `GB00 → CLK0` y `CLK1` | `HCLK_OUT1 → FCLKA` |

Ambas rutas se comprobaron en el mismo diseño enrutado. La `rPLL` quedó
en `X55Y45/PLL`: `CLKOUTD` viaja por GCLK; `CLKOUT` por
`GCLK → TBDHCLK0 → HCLK_IN0 → sección 1 → HCLK_OUT1`. nextpnr
confirmó recursos de reloj exclusivos para `CLK_BYTE` y `CLK_HS`;
[`verify_route.py`](tools/verify_route.py) verifica además los sumideros
de ambos carriles en `build/hs_serializer/probe_routed.json`.

**Cobertura temporal:** nextpnr reportó 498,50 MHz para el peor camino
medido en `CLK_BYTE` (↓→↓ del contador de estímulo; pasa 55 MHz). El
informe detallado no contiene endpoints de datos en `OSER8` ni un
resultado temporal para `CLK_HS`. Esto deja pendientes el setup/hold
de ↓ a ↑PCLK, la fase PCLK/FCLK y de rearme en ambas E/S, y el skew
entre carriles. Los objetivos SDC de la sonda fijan los periodos
nominales; no prueban la fase de relojes relacionados ni los márgenes
del driver final.

[dphy]: https://download.tek.com/manual/MIPI-D_PHY-Measurements-Setup-Library-MOI-DPOJET-EN-US_077042801.pdf
[ug289]: https://cdn.gowinsemi.com.cn/UG289E.pdf
[prim-sim]: https://github.com/BigPig-Bro/Gowin/blob/cb6df4cb3b74ebaffdb3df930dfd3073eca2ec00/Gowin_sim/gw2a/prim_sim.v
