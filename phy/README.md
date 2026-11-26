# PHY Gowin — enlace hasta los pads

[Diagrama editable](docs/PHY.drawio) · [Tabla de flancos](docs/tabla_flancos.md)

[`phy`](src/phy.v) conecta `CLOCK_GEN`, `PHY_CTRL`, dos `HS_SERIALIZER`,
`CLOCK_DDR` y `DPHY_PADS`. `phy_ctrl_gowin` aplica la secuencia de reloj
no continuo para el perfil candidato: 55 MHz de byte, 220 MHz de reloj HS,
dos carriles de 440 Mbit/s y 1166 ciclos por línea. Configuración de
`MIPI_TX`: `LP_DIV=6`, `T_CLK_START=27`, `T_LPX/PREP/ZERO/TRAIL=4/3/7/4`,
`C_LINE=1166`. El TOP `phy` recibe `RESET` de PLL y `RST_BYTE` por separado.
[`PHY_SUPERVISOR`](phy_supervisor/README.md) puede suministrar ambos resets
desde una base de tiempo independiente. El target LP de LiteX conserva su
propia inicialización y sus pads HS aislados.

## Simulación

```sh
pixi run --locked make -C phy test
pixi run --locked make -C phy test INIT_HZ=5000 SIM_DELAY=1
pixi run --locked make -C phy test INIT_HZ=5000 SIM_DELAY=1 \
  GOWIN_SIM=/ruta/absoluta/a/gw2a/prim_sim.v
```

`test` usa las esperas completas de la ROM a 55 MHz. `INIT_HZ=5000` acelera
solo las esperas LP: el banco comprueba su número exacto de ciclos a la
escala configurada. `SIM_DELAY=1` ensaya 32 taps sin calibrarlos para la
placa. `GOWIN_SIM` usa las primitivas de E/S de la biblioteca funcional
GW2A (contrastado con 1.9.14); en ambos casos la `rPLL` es el modelo local
que permite parar las salidas conservando `LOCK_RAW`. `sim` ejecuta el
mismo banco, vuelca FST y lo abre; `wave` abre el último volcado.

El banco del PR #11 conserva sus pruebas lógicas. La variante Gowin reutiliza
su comparación con la ROM y sus referencias RGB y CRC, con
`INIT_SEQUENCER`, `VIDEO_SOURCE`, `MIPI_TX` y PHY reales:

- Reconstruye 18 selectores `87`, 204 bytes DSI y las 18 esperas —
  15 de 9 ms, dos de 65 ms y el WAIT final de 7 ms — sin HS antes de END.
- Reconstruye SoT, cabecera `3E 70 08 13`, 2160 bytes RGB y CRC desde los
  pares diferenciales, en orden D0/D1. Las barras dan `EE/7E`; blanco da
  `25/34` y 1080 lecturas, con `FFFF` inyectado en el banco.
- Verifica CLK adelantado, dos líneas a 1166 ciclos de distancia,
  polarización antes del OE, ambos trails, post, pulso final completo y
  vuelta a LP11. Las variantes directa y con retardo dieron ≥92,37 ns de
  trail, ≥227,27 ns de CLK después del corte de datos y ≥99,20 ns de
  HS-0 de CLK después de su última bajada (tiempos del modelo).
- Con ambos relojes detenidos y `LOCK_RAW` alto, aserta el corte que
  aplicaría el supervisor y comprueba alta impedancia en los doce pads.
  Tras el reset común verifica de nuevo la ROM completa y una línea
  desde SoT, W0 y el primer píxel.

## Síntesis y rutas

```sh
pixi run --locked make -C phy synth
pixi run --locked make -C phy route
pixi run --locked make -k -C phy audit
```

La [sonda offline](tools/route_probe.v) sintetiza la misma cadena completa
con la ROM de inicialización y la fuente de barras. Usa `-nobram` en la
sonda: el mapeo automático de la ROM a `SP` introdujo una inversión de
`CLK_BYTE` sobre LUT y una rama por interconexión ordinaria. Con ROM en
lógica, nextpnr 0.11.1 enrutó ambas variantes sin ese aviso. Verificación:
seis TBUF, tres TLVDS_TBUF, OEN dinámicos dominados por `ISO`, `Q0`
locales y HCLK/GCLK dedicados en los tres destinos de E/S. Fmax de
`CLK_BYTE` reportada: 134,05 MHz directa y 99,05 MHz con `IODELAY`.
Los informes no cierran fase, setup/hold de los serializadores, margen
del OE ni niveles eléctricos.

## Fusibles y trabajos pendientes

Con Apicula 0.32 instalada, ambas variantes pasan `audit` mediante el
[adaptador mixto](dphy_pads/tools/apicula_mixed.py). El adaptador corrige
la selección de banco y de drive antes de codificar. La auditoría
comprueba el banco 0 a 1,2 V y sus seis TBUF LVCMOS12 con DRIVE=8, slew
FAST y pulls desactivados, y el banco 1 a 2,5 V con los tres pares
LVDS25/TLVDS_TBUF. Comprueba también los bits seleccionados en el mapa
final de ambas variantes y se detiene antes de serializar.

Antes del adaptador, el mismo comando daba 13 errores por variante:
seis `DRIVE=UNKNOWN`, seis `BANK_VCCIO=1.2` en los pads HS y uno en
el banco 1. Los informes quedan en
`build/phy/{direct,delay}/fuse_review.json`, con los hashes del JSON,
la base del dispositivo y el codificador original y adaptado. Son
resultados de empaquetado en memoria. La auditoría del target LP
sigue usando el codificador original, también para backlight.

El [TOP de FPGBC](../gateware/docs/fpgbc_white.md) conecta supervisor,
backlight y blanco fijo. `ISO` se expone para apagar el backlight si el
PHY aísla el enlace. Una línea blanca correcta verifica el enlace
modelado. Quedan la coordinación física del arranque del LCD, el cierre
de fase y red eléctrica y la validación de una receta de cuadro completo.
