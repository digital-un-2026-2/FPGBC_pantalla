# CLOCK_GEN — diseño y factibilidad

[Datapath editable](docs/CLOCK_GEN.drawio) · [RTL aislado](src/clock_gen.v).

Una `rPLL` del **GW2AR-LV18EQ144PC8/I7** (`GW2AR-18C`, `EQ144P`) puede
generar el perfil candidato de **55/220 MHz** dentro de los límites del
fabricante. La sonda se enrutó hasta el grupo HCLK superior, pero no
demuestra la ruta completa a los tres destinos de E/S. El perfil equivale a
**440 Mbit/s por carril**:
cuatro ciclos de `CLK_HS`, con dos flancos útiles por ciclo, por cada ciclo
de `CLK_BYTE`. No es una medición del enlace original.

## Datapath e interfaz

Según `Docs/MIPI_PHY_bloques.pdf` de `digital_UN/MIPI_LCD`, el generador
entrega los dos relojes internos y el estado de la PLL. El `LOCK` dibujado
entre `CLOCK_GEN` y `PHY_CTRL` se llama **`LOCK_RAW`** en el
[contrato de `PHY_CTRL` del PR #12][pr12]; el `LOCK` que vuelve a `MIPI_TX`
es otro. Todos los puertos del generador son de **1 bit**.

| Puerto | Dirección | Contrato propuesto |
|---|---|---|
| `CLK_REF` | Entrada | Referencia nominal de 40 MHz del pin 11. |
| `RESET` | Entrada | Reset físico de la `rPLL`, asíncrono activo en 1. No es `RST_BYTE` ni el reset del panel. |
| `CLK_HS` | Salida | `CLKOUT`, 220 MHz, fase base común. No es la señal `HS_CLK` que se reenvía al panel. |
| `CLK_BYTE` | Salida | `CLKOUTD`, 55 MHz, derivado de `CLKOUT` dentro de la misma PLL. |
| `LOCK_RAW` | Salida | `rPLL.LOCK` directo, no sincronizado, sin filtrar ni forzar por lógica de byte. |

No hay registros de usuario, FSM, conmutador de reloj ni `CLK_REQ` dentro
de `CLOCK_GEN`. La PLL tiene realimentación interna (`CLKFB_SEL=internal`),
divisores estáticos, bypass desactivado y `RESET_P=0`. `CLKOUTP` y `CLKOUTD3`
no se usan. `CLK_REQ` gobierna la reserva de la salida física a través de
`PHY_CTRL`; no arranca, detiene ni cambia los relojes internos.

## Frecuencias, divisores y restricciones

Límites de [DS226-2.7E][ds226], tabla 3-20, columna **C8/I7**. La
codificación estática se toma de [UG286-2.0.2E][ug286], §5.1, tablas 5-1 a 5-6.

| Nodo | Frecuencia / periodo nominal | Cálculo y selección | Ruta y restricción |
|---|---:|---|---|
| `CLK_REF` → `CLKIN` | 40 MHz / 25 ns | `FCLKIN=40 MHz` | Pin 11 (`IOL27A/GCLKT_7`, banco 7) → red de reloj interna → `rPLL.CLKIN`. Es un pin GCLK, no una entrada dedicada de PLL. Rango 3–500 MHz; a 40 MHz comprobar duty de entrada (mín. 25 %) y jitter de periodo (máx. 1 ns). |
| PFD | 20 MHz / 50 ns | `40 / 2`, `IDIV_SEL=1` (`IDIV=2`); `220 / 11` por realimentación, `FBDIV_SEL=10` (`FBDIV=11`) | Interno; 3–500 MHz. |
| VCO | 880 MHz / ≈1,136 ns | `220 × 4`, `ODIV_SEL=4` | Interno; 500–1250 MHz. `ODIV=2` daría 440 MHz, por debajo del mínimo. |
| `CLK_HS` | 220 MHz / ≈4,545 ns | `CLKOUT = 40 × 11 / 2` | Rango de salida PLL 3,90625–625 MHz. Exigir HCLK de Bank 1 hasta `FCLK` de D0, D1 y `CLOCK_DDR`, no ruteo por LUT ni por interconexión ordinaria. |
| `CLK_BYTE` | 55 MHz / ≈18,182 ns | `CLKOUTD = 220 / 4`, `DYN_SDIV_SEL=4`, `CLKOUTD_SRC=CLKOUT` | Salida dividida en hardware, dentro del rango; red primaria GCLK/PCLK al tejido y a `PCLK` de los dos `OSER8`. Sin divisor en tejido, sin un segundo reloj de byte. |
| `PCLK` local de `CLOCK_DDR` (fuera de `CLOCK_GEN`) | 110 MHz / ≈9,091 ns | `220 / 2` mediante `CLKDIV` | HCLK de Bank 1 a `CLKDIV.HCLKIN`; salida a la red primaria y a `OSER4.PCLK`. Verificar ambos caminos junto con el `FCLK` sin dividir. |

En el análisis de tiempos, declarar 25 ns para la referencia y comprobar
que 220 y 55 MHz se reconocen como **relojes generados relacionados** en
los nodos reales de la PLL y de E/S. No marcarlos como asíncronos para
ocultar caminos. Revisar ambos flancos, anchura de pulsos, skew y
setup/hold, incluido el presupuesto de medio ciclo de byte (≈9,091 ns).
La relación 4:1 no fija por sí sola el flanco de carga ni la latencia de
`OSER8` respecto al contrato `↓` a `↓` de `PHY_IF`.

### Rutas a los destinos fijos

El [pinout UG115-1.7.2E][ug115] (columna EQ144P, pp. 9 y 16) y la
[plataforma FPGBC](../../gateware/platforms/fpgbc.py) sitúan **los tres pares
HS en Bank 1, lado superior del dado**. `A/B` conserva el orden P/N:

| Destino (fuera de alcance) | Pines P/N de FPGA | Sitio de E/S | Relojes que necesita |
|---|---|---|---|
| D0 | 117 / 116 | `IOT40A/B` | `OSER8.FCLK` desde HCLK; `OSER8.PCLK` desde GCLK/PCLK. |
| D1 | 115 / 114 | `IOT42A/B` | Las mismas redes HCLK y GCLK/PCLK que D0. |
| CLK | 113 / 112 | `IOT48A/B` | El mismo HCLK a `FCLK` de la E/S para `CLOCK_DDR`; el reloj paralelo local se describe abajo. |

**Documentado:** DS226 §2.7, figuras 2-12/2-13, describe la red primaria,
HCLK y el puente entre bancos; [UG289-2.2.1E][ug289] §4.3 documenta los
dos relojes de `OSER8` y `OSER4`. La tabla 3-17 de DS226 da máximos del
*gearbox* de 1200 Mbit/s (`OSER8`) y 800 Mbit/s (`OSER4`): 440 Mbit/s
cabe en ambos. No usar `ODDR` 2:1 como atajo a 220 MHz DDR: su máximo
publicado es 400 Mbit/s. Esto no comprueba el empaquetado con una salida
diferencial concreta ni la adaptación descrita en [hardware](../../docs/hardware.md).

**Cotejo estático de las E/S:** la base `GW2A-18C` de Apicula 0.32
contiene el encapsulado y grado exactos. Los tres sitios tienen `IOLOGICA`
y pueden recibir `FCLKA` desde las mismas líneas superiores `HCLK_OUT1`
o `HCLK_OUT3`. Como punto de partida, una PLL inferior izquierda de la
base (`BLPLL0`) tiene las siguientes conexiones candidatas:

- `GCLKT_7` → `PCLKL0` → HCLK izquierdo → `rPLL.CLKIN`. El pin de placa
  no permite presuponer la conexión directa de un pin dedicado PLL.
- `CLKOUTD` (`BLPLL0CLK3`) → espina de distribución GCLK → `PCLK` de
  los dos `OSER8` y dominio de byte.
- `CLKOUT` (`BLPLL0CLK0`) → HCLK inferior → puente → HCLK de Bank 1
  (`HCLK_OUT1`, por ejemplo) → los tres `FCLK`. La base muestra
  `BLPLL0CLK0` como fuente de `HCLK_IN1` inferior (`X27Y54`) y de allí la
  salida de banco; arriba (`X27Y0`), `HCLK_BANK_IN0` puede alimentar
  `HCLK_OUT1`. **No se encontró en esa base el tramo de salida de banco
  al mux central**.
  Tampoco se puede dar por hecho un atajo por las PLL superiores: la
  base marca deshabilitados los sitios de `X0Y9` y `X55Y9`. Esto es una
  limitación de la comprobación con la base abierta, no una demostración
  de imposibilidad en silicio ni una restricción de colocación definitiva.

La [sonda enrutada](#síntesis-y-enrutado-aislados) usó otra ruta al grupo
superior: de una PLL inferior derecha por GCLK a `TBDHCLK0`, sin pasar por
el puente interbanco. Es una alternativa a contrastar al colocar las E/S,
no una colocación fija ni una demostración de los tres `FCLK`.

## Fase del reloj reenviado (propuesta para el vecino)

[IPUG948-2.3E][ipug948], §6.1.7, describe la relación de 90° para centrar
los flancos del reloj entre los flancos de datos. En este perfil un UI
es ≈2,273 ns y **90° de 220 MHz son ≈1,136 ns**, medio UI. Invertir un
reloj DDR intercambia flancos pero no los centra.

`CLOCK_GEN` entrega **un único `CLK_HS` sin desfase añadido**. Para no
introducir un segundo HCLK ni ampliar su interfaz, la opción a evaluar
para `CLOCK_DDR` es usar el mismo HCLK en un `OSER4` con patrón alternante.
Su `PCLK` sería **110 MHz**, generado localmente por `CLKDIV` ÷2 (UG286
§5.5), sin tocar `CLK_BYTE`. El HCLK superior de la base puede ramificarse
hacia `CLKDIV.HCLKIN` además de `FCLK`, y `THCLK0CLKDIV` es fuente de la
red primaria; falta verificar la selección simultánea de esos caminos.
El patrón produce una onda de 220 MHz; la habilitación de la salida y el
ajuste de fase pertenecen al vecino. La ruta local `OSER4.Q0` →
`IODELAY` de salida (UG289 §4.3.3 y §4.4.1)
permite ajustar los flancos antes del driver. DS226, tabla 2-4, da
350 ps típicos de offset más 18 ps típicos por paso, de 0 a 127 pasos:
el orden de magnitud permite ensayar el desplazamiento, pero no fija
un tap sin caracterizar el resto de los caminos CLK/D0/D1.

`rPLL.CLKOUTP` también permite un desfase nominal de 90° (UG286,
tabla 5-7), pero usarlo en paralelo con `CLKOUT` para el par CLK requeriría
otra ruta HCLK hasta el mismo banco y revisar la conexión interna del
contrato. No se propone ese puerto. Ni el ajuste local ni una fase exacta
de PLL validan los flancos en el panel: faltan temporización del
serializador, skew de la red, jitter, duty y medición en los pares.

## Reset, adquisición y recuperación

UG286, tabla 5-2, define `LOCK` de la PLL como 1 = enganchada, 0 = no
enganchada. Advierte de pulsos espurios al adquirir lock y pide
**observarlo continuamente durante al menos 2 ms**. El `TLOCKMAX=1 ms`
de DS226 es un tiempo de adquisición, no de detección de pérdida. No se
encontró garantía de que `LOCK_RAW` caiga en un plazo definido, o siquiera
que caiga si desaparece `CLK_REF`. Si se detiene solo la distribución de
`CLK_BYTE`, la realimentación de la PLL puede seguir enganchada. `LOCK_RAW`
no demuestra la presencia de flancos en los consumidores.

| Momento | Comportamiento propuesto |
|---|---|
| Arranque o recuperación con referencia inestable | El [supervisor](../phy_supervisor/README.md) mantiene `RST_BYTE=1` y la salida física inhibida. Con `CLK_REF` estabilizado, mantiene cumplido el mínimo de 10 ns de `RESET=1` de la PLL (DS226) y lo libera sin depender de `CLK_BYTE` ni de `LOCK`. No se admite tráfico ni se cuenta con flancos válidos durante el reinicio de la PLL. |
| Adquisición | Mantener `RST_BYTE=1` mientras se comprueba actividad de `CLK_BYTE` y se observa `LOCK_RAW` alto estable durante ≥2 ms. No esperar al `LOCK` de `PHY_CTRL` para liberar el reset ni realimentar `!LOCK` al reset de la PLL. |
| Flancos válidos | Con `LOCK_RAW` ya estable, sostener `RST_BYTE=1` en al menos un `↑` válido y el `↓` siguiente, luego liberarlo cumpliendo setup/hold. `PHY_CTRL` cualifica su `LOCK` en dos `↓`; eso no sustituye los 2 ms. El rearme requiere reset observado y peticiones en reposo; no reanuda la transacción abortada. |
| Reset lógico normal | `RST_BYTE` no reinicia la PLL. `CLK_BYTE` sigue corriendo en reposo y durante ese reset si la referencia y la PLL están operativas. Un reset físico de la PLL es distinto: no se prometen flancos durante su reinicio. |
| Pérdida en servicio | `PHY_CTRL` corta sin flancos si cae `LOCK_RAW` o se le aserta `RST_BYTE`. Ante `LOCK_RAW` alto y un reloj detenido, el supervisor detecta la ausencia de `CLK_REF` o `CLK_BYTE` desde el oscilador independiente y aserta `RST_BYTE`. Su rearme garantiza el reset común al volver los flancos. |

## Pruebas de CLOCK_GEN

Desde la raíz, con el entorno bloqueado:

```sh
pixi run --locked make -C phy/clock_gen test
pixi run --locked make -C phy/clock_gen route
```

`test` usa el wrapper real contra un [modelo ideal](TB/rpll_model.v) que
solo se compila en simulación. Pasaron las comprobaciones de periodo,
cuatro subidas y cuatro bajadas de HS por ciclo de byte, propagación
de `LOCK_RAW` entre flancos de byte, continuidad de los relojes durante
esa caída inyectada y recuperación de ambos flancos tras el reset
del modelo. La inyección cambia el estado crudo sin parar la referencia:
no demuestra comportamiento ante pérdida física del reloj, fase ni jitter.
`test` no vuelca ondas; `sim` genera `build/clock_gen/clock_gen_TB.fst`
y lo abre en GTKWave. `wave` abre ese último volcado.

### Síntesis y enrutado aislados

`synth` usa Yosys (`gw2a`) sin el modelo ni pads en el módulo. `route`
verifica que la netlist contenga una sola `rPLL` con los valores de la tabla
y los puertos cableados directamente. Con esa misma netlist, la
[sonda](tools/route_probe.py) fija el reset de la PLL a cero, conserva como
única E/S el pin de referencia 11 y añade cargas internas: dos registros
de prueba y un `CLKDIV` en el grupo HCLK superior. El `CLKDIV` es un
sumidero de prueba, no parte de `CLOCK_GEN` ni de una implementación de
`CLOCK_DDR`. No se genera bitstream ni se conecta ningún par del panel.

**Resultado (Yosys 0.69+, nextpnr 0.11.1, Apicula 0.32):** la PLL quedó en
`X55Y45/PLL` del `GW2AR-LV18EQ144PC8/I7`. Las redes de la sonda pasaron
con solo recursos de reloj según nextpnr; las rutas se guardan en
`build/clock_gen/probe_routed.json` y `probe.log`.

| Red de la sonda | Ruta observada |
|---|---|
| Referencia | Pin 11 (`X0Y26/IOBA`) → `PCLKL0` → GCLK → `CLKIN` de la PLL. |
| `CLK_BYTE` | `CLKOUTD` (`BRPLL0CLK3`) → GCLK → registro interno de prueba. |
| `CLK_HS` | `CLKOUT` (`BRPLL0CLK0`) → GCLK → `CLK2`/`TBDHCLK0` → `HCLK_IN0` → `X27Y0/CLKDIV_HCLK0_SECT0.HCLKIN`. Sin LUT en esa ruta de reloj. |
| Salida del divisor de prueba | `THCLK0CLKDIV` → GCLK → segundo registro de prueba. |

Los periodos del SDC de la sonda son objetivos nominales, no mediciones
ni restricciones de integración. No hay Fmax de datos en esta prueba.
Se enrutó **la sección 0** del divisor. La base muestra `HCLK_IN0` como
fuente posible también de la sección 1, que puede llevar el reloj sin
dividir por `HCLK_OUT1` a `IOT40A`, `IOT42A` e `IOT48A`. Esa conexión
es evidencia topológica; no se enrutó con los `FCLK` de las E/S como
sumideros ni junto con sus `PCLK`.

### Antes de conectar los serializadores

1. Verificar las rutas **simultáneas** de `FCLK` y `PCLK` en los sitios
   fijos, incluida la rama del divisor local de `CLOCK_DDR` si se adopta.
   Si nextpnr no las cierra, contrastar con Gowin EDA; no aceptar un
   fallback por interconexión ordinaria. Cerrar setup/hold en ambos
   flancos y el flanco efectivo de carga frente a SoT y CRC.
2. Decidir y validar el método de fase del reloj reenviado. Medir
   CLK/D0/D1, duty, jitter y niveles en la red real solo con revisión de
   E/S y autorización por separado.
3. Conectar el supervisor al TOP para la protección ante pérdida de
   referencia o parada de `CLK_BYTE`, la cualificación al arrancar y el
   rearme. El ensayo de `CLOCK_GEN` no garantiza que `LOCK_RAW` caiga sin reloj.

[pr12]: https://github.com/digital-un-2026-2/FPGBC_pantalla/blob/64b009ffc2f4cd6613ecbb7723dd0945f84227dc/phy/phy_ctrl/README.md
[ds226]: https://cdn.gowinsemi.com.cn/DS226E.pdf
[ug286]: https://cdn.gowinsemi.com.cn/UG286E.pdf
[ug115]: https://cdn.gowinsemi.com.cn/UG115E.pdf
[ug289]: https://cdn.gowinsemi.com.cn/UG289E.pdf
[ipug948]: https://cdn.gowinsemi.com.cn/IPUG948E.pdf
