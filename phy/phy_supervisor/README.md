# PHY_SUPERVISOR — reloj y reset del enlace

[Diagrama editable](docs/PHY_SUPERVISOR.drawio) · [RTL](src/phy_supervisor.v)

Bloque auxiliar Gowin para el PHY de 40/55/220 MHz. Dos intercambios
independientes `REQ/ACK` comprueban flancos de `CLK_REF` y `CLK_BYTE` incluso
con `LOCK_RAW` alto y durante reset de byte. Cada solicitud se mantiene hasta
recibir la respuesta; el reloj probado tiene que capturar la solicitud con
dos flancos de bajada antes de devolverla. La pérdida de lock y el reset
lógico tienen un camino de corte asíncrono, con observación sincronizada
separada para volver a cualificar. El monitor exige 62 000 ciclos válidos
antes de permitir un nuevo par de flancos ↑/↓ de reset con lock.

| Intervalo | Presupuesto |
|---|---|
| `CLK_WD` | `OSC` → `BUFG`, `FREQ_DIV=10`, 25 MHz nominal; 19–31 MHz para cálculo (DS226-2.7E §2.11 y tabla 3-19). |
| Falta de flancos | 64 ciclos sin respuesta; hasta 70 desde el último flanco contando el ACK en vuelo y la decisión: <3,7 µs de presupuesto lógico más propagación a los pads. |
| Reset de PLL | Al menos 64 ciclos con actividad de referencia antes de salir de reset: ≥2,06 µs, frente a ≥10 ns de DS226. |
| Ventana de adquisición | 2,00–3,27 ms de actividad y lock cualificado por el supervisor. Una caída capturada del lock borra el avance. |
| Plazo de un intento | 4,00–6,53 ms antes de reciclar la PLL. `RST_LINK` mantenido cancela el plazo mientras el enlace está en reset. |

Los plazos se calculan con el oscilador activo y latencia CDC normal.
Son vigilancia de actividad, no una medida de frecuencia, calidad de reloj
ni verificación de `CLK_HS` o de cada rama de distribución por separado.

## Requisitos de conexión del TOP

Todos los puertos del supervisor son de 1 bit:

| Puerto | Conexión |
|---|---|
| `CLK_REF` (entrada) | La misma red de referencia de 40 MHz que entra en `phy.CLK_REF`. |
| `CLK_BYTE` (entrada) | `phy.CLK_BYTE`: `CLKOUTD` de la rPLL en la red que usan los consumidores de byte. |
| `LOCK_RAW` (entrada) | `phy.LOCK_RAW`: el mismo nodo de la rPLL que recibe `PHY_CTRL`, mediante un puerto RTL, sin pin físico. |
| `RST_SUP` (entrada) | Reset de arranque/general activo alto, asertable sin los relojes vigilados. Mantenerlo activo al arrancar y durante la configuración del enlace. |
| `RST_LINK` (entrada) | Petición opcional de reset lógico activo alto; mantener a 0 si no se usa. Con relojes sanos conserva la PLL activa. Toda petición asíncrona debe cumplir el ancho mínimo de borrado/preset de la FPGA. |
| `RESET` (salida) | Solo a `phy.RESET` (reset de la rPLL). |
| `RST_BYTE` (salida) | Reset común de `phy`, `MIPI_TX`, `INIT_SEQUENCER` y `VIDEO_SOURCE`. Aserción asíncrona; liberación registrada tras un ↑ de `CLK_BYTE`, con un ↑ y un ↓ de reset ya observados. |

El aislamiento sigue la ruta `phy → PHY_CTRL → ISO → DPHY_PADS`.
El TOP decide `PANEL_RST`, alimentación y backlight. La reemisión de la ROM
desde la dirección 0 restablece el estado de la cadena digital; el TOP debe
coordinar la secuencia que deja al panel listo para recibirla.

## Validación reproducible

Desde la raíz:

```sh
pixi run --locked make -C phy/phy_supervisor test
pixi run --locked make -C phy/phy_supervisor route
pixi run --locked make -C phy test INIT_HZ=5000 SIM_DELAY=1
pixi run --locked test-gateware
```

`test` ejecuta el escenario del supervisor a 19 y 31 MHz con el PHY y los
pads modelados. Se cubren arranque sin referencia, intento sin flancos de
byte, `LOCK_RAW` inestable, cortes independientes de referencia y byte
forzando lock alto incluso durante el aislamiento, y reset lógico en
payload HS. Se comprueban los doce pads en alta impedancia, el nuevo par
↑/↓, los 18 paquetes y 204 bytes de la ROM desde los pads y el reinicio de
vídeo desde SoT, cabecera y primer píxel. `INIT_HZ=5000` escala en el banco
las esperas de la ROM; la frecuencia de byte, los tiempos LP/HS y los
plazos del supervisor no cambian. `test-at-rate` admite `OSC_HZ`, `SIM_DELAY`
y `GOWIN_SIM`; `sim` y `wave` usan `build/phy_supervisor/phy_supervisor.fst`.

`route` usa la sonda offline de PHY con el supervisor, sin TOP de placa ni
archivo de programación. Con `BUFG`, `CLK_WD` se enrutó sin avisos y pasó la
restricción de 31 MHz en las variantes directa y con `IODELAY`; los informes
quedan en `build/phy_supervisor/{direct,delay}/`. En el TOP se debe volver a
revisar la red de reloj, los caminos de medio ciclo, la distribución del
corte asíncrono y los cruces/reset (incluido recovery/removal). El enrutado
offline no valida niveles, fase ni la aceptación de un cuadro por el LCD.
