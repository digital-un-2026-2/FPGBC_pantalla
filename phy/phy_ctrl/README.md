# PHY_CTRL — control de modo dentro del PHY

La [integración Gowin](../README.md) usa `phy_ctrl_gowin` con modos y OE
por grupo. Este documento describe `phy_ctrl`, la implementación de slots
del PR #12 que se conserva con su banco aislado. Ambos usan `phy_ctrl_guard`.

[Diseño editable: Flujo, Datapath y FSM](docs/PHY_CTRL.drawio).
[`phy_ctrl`](src/phy_ctrl.v) controla la habilitación de los drivers LP, de
datos HS y del reloj reenviado. No es `PHY_IF`, no recibe datos ni implementa
PLL, serializadores, pads o TOP. Sigue `MIPI_PHY_bloques.pdf` del proyecto
vecino y el [modelo de consumo del PR #11](../../mipi_tx/TB/mipi_tx_phy_model.v)
para la interfaz lógica con `MIPI_TX`.

| Señal | Contrato lógico |
|---|---|
| `CLK_BYTE`, `RST_BYTE` | Reloj compartido, independiente de `CLK_REQ`. Reset común activo en 1; el supervisor debe cubrir un ↑ y el ↓ siguiente válidos. |
| `HS_REQ`, `CLK_REQ` | Peticiones de `LINK_FSM` en `CLK_BYTE`; cambian después de ↑ y se muestrean en ↓. `CLK_REQ` reserva el reloj físico, no el reloj de byte. |
| `LOCK_RAW` | Estado crudo del generador de reloj, local al PHY. Su caída corta incluso sin `CLK_BYTE`; puede quedarse alto ante una parada. |
| `LOCK`, `READY` | Retornos en `CLK_BYTE`. `LOCK` se cualifica en dos ↓; `READY` anuncia LP disponible y sin reserva HS, incluso antes de ambas peticiones. `LINK_FSM` arbitra los paquetes LPDT; `PHY_CTRL` no deduce actividad LPDT de sus símbolos. |
| `LP_EN`, `HS_EN`, `CLK_EN` | Habilitaciones lógicas activas en 1. `LP_EN` corresponde a los tres pares LP, `HS_EN` a HS de D0/D1 y `CLK_EN` a HS del par CLK. No se solapan LP y HS/CLK. |
| `CLK_ARM`, `ISO`, `SER_MODE[1:0]` | Solo dentro del PHY. Preparación del reloj; corte con prioridad sobre las habilitaciones y descarte de la carga; y selección de slot del serializador: `00` OFF, `01` ZERO, `10` WORD, `11` TRAIL. |

`LP_P[2:0]`, `LP_N[2:0]` y `HS_BYTE0/1[7:0]` van de `PHY_IF` a sus vecinos
dentro del PHY, no a este bloque. No hay puerto nuevo en `MIPI_TX`, `LP_REQ`,
`PK_START`, `PK_DONE`, `SOT_EN` ni `VALID` por palabra. LP11 es un valor de
datos; no equivale a dejar los pads en alta impedancia.

## Flancos, drenaje y aborto

- La FSM decide en ↑. En ↓ se muestrean peticiones, actualiza el temporizador
  y se aplica el propietario del slot de driver. Los OE y el modo se decodifican
  combinacionalmente. `CLK_ARM` se presenta durante el preámbulo LP, pero
  `CLK_EN` no se aplica hasta el primer slot ZERO. Hay medio ciclo de separación
  lógica antes de aplicar los drivers HS/CLK y antes de volver a habilitar LP.
- Si `↓z` muestrea el alza de `HS_REQ`, se carga SoT en `↓(z+T_ZERO+1)`.
  Ambos serializadores toman el registro previo de `PHY_IF` en cada ↓ en modo
  WORD. El ↓ que muestrea la caída de `HS_REQ` todavía carga el CRC. El ↑
  siguiente cambia el modo para el **próximo** ↓, no para la palabra en curso.
  Este traspaso supone un slot entero para el CRC, sin carga adicional antes
  de trail. `T_ZERO` y `T_TRAIL` deben coincidir con los de `LINK_FSM`.
- Tras `T_TRAIL` slots, el slot de salida retira HS de D0/D1 pero mantiene
  `CLK_EN`. Un ↑ posterior con ambas peticiones bajas retira `CLK_EN`; solo
  el ↓ siguiente restaura el driver LP y `READY`. La caída de `CLK_REQ` por
  sí sola no interrumpe una ráfaga ya reservada.
- [`phy_ctrl_guard`](src/phy_ctrl_guard.v) inhibe OE con `ISO` al asertar
  `RST_BYTE` o perder `LOCK_RAW`, sin esperar flanco. Los retornos de byte
  pueden ser obsoletos sin reloj y no gobiernan ese corte. El rearme exige reset
  común observado con reloj recuperado tras perder lock, estado seguro y
  peticiones bajas antes de anunciar disponibilidad. El supervisor futuro
  debe sostener o reaplicar el reset común: recuperar lock no reanuda ni LPDT
  ni la ráfaga parcial.

## Prueba aislada

Desde la raíz:

```sh
pixi run --locked make -C phy/phy_ctrl test
pixi run --locked make -C phy/phy_ctrl sim
pixi run --locked make -C phy/phy_ctrl wave
```

`test` corre sin ondas en p0 (`T_ZERO/T_TRAIL=1/1`) y p1 (`7/4`), los límites
lógicos del banco de `MIPI_TX`. `sim` corre las mismas comprobaciones en p1
por defecto (`SIM_PROFILE=0` elige p0), vuelca
`build/phy_ctrl/phy_ctrl_TB.fst` y lo abre con GTKWave. `wave` reabre la
última traza sin recompilar.

El [banco](TB/phy_ctrl_TB.v) instancia solamente el RTL de `PHY_CTRL`.
Modela las peticiones y los registros de `PHY_IF` en los flancos del PR #11.
Comprueba los símbolos LP sin HS, `LOCK` antes de `READY`, la carga de SoT y
1083 palabras con un CRC de prueba, la ausencia de cargas posteriores y la
retención del reloj. Incluye patrones `00/00`, `B8/B8` y el valor del CRC
dentro de los datos para detectar interpretaciones por contenido. Detiene
`CLK_BYTE` para probar reset antes del drenaje y pérdida de lock durante
datos; comprueba que los pares queden aislados sin flancos, que `LOCK` pueda
volver sin `READY` antes del reset común y que una ráfaga nueva empiece en SoT.
Los [vecinos](TB/phy_ctrl_neighbors_model.v) modelan slots y drivers ideales,
no serialización DDR ni temporización física.

## Pendiente al integrar

- Verificar setup/hold, fase relativa y latencia del serializador en el
  traspaso ↓ a ↓. Si la primitiva requiere otro flanco o su latencia cruza un
  slot, hay que demostrar un adaptador compatible o revisar el contrato antes
  de desplazar SoT, CRC o trail.
- Supervisar la actividad de reloj independientemente de `LOCK_RAW`;
  llevar `ISO` hasta el OE real, incluso si algún adaptador guarda una
  habilitación. Revisar que se preserven las ventanas de conducción sin pulsos
  tras síntesis y enrutado.
- Confirmar un OE de reloj independiente de datos HS, modo del reloj,
  adelanto, retención, patrón de zero/trail y separación real entre drivers.
  La revisión eléctrica de pulls, ramas LP y la red de 100 Ω por conductor no
  forma parte de este banco. Ningún tiempo modelado es un ajuste de placa.
