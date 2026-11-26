# Integración PHY Gowin — diseño y tabla de flancos

[Diseño editable](PHY.drawio) · Contrato: `MIPI_LCD/Docs/MIPI_PHY_bloques.pdf`
· Base: `origin/main` `c04f9e3` (PR #17) · [Implementación y resultados](../README.md).

## Responsabilidades y cambios propuestos

| Bloque | Diseño propuesto |
|---|---|
| TOP `PHY` | Solo conexiones. `CLOCK_GEN` distribuye `CLK_BYTE`, `CLK_HS` y `LOCK_RAW`; `PHY_CTRL` gobierna modos y ventanas; dos `HS_SERIALIZER` consumen D0/D1 respectivamente; `CLOCK_DDR` entrega `HS_CLK`; `DPHY_PADS` conecta los doce pads de FPGA. Conservar los puertos de `MIPI_TX` y el orden `{CLK,D1,D0}`. |
| `LINK_FSM` | Agregar una fase temporizada `CLK_PRE` a la admisión de vídeo: `CLK_REQ=1`, datos todavía LP11, `HS_REQ=0`. Proponer el parámetro de elaboración `T_CLK_START=27` para este perfil y `0` por defecto para preservar el comportamiento de los bancos del PR #11. Pasarlo a través de `MIPI_TX` y sumarlo a `C_ACTIVE`; conductor de línea LP01→LP01 y arbitraje de init se conservan. `HS_REQ`, SoT, `PK_START`, CRC y EOT mantienen su relación. |
| `PHY_CTRL` | Sustituir el `LP_EN` común por `LP_DAT_MODE[1:0]` y `LP_CLK_MODE[1:0]`, con OE separados; generar `LP_CLK_PN[1:0]` para el par CLK. D0/D1 reciben sus símbolos registrados de `PHY_IF`; `LP_P/N[2]` de `PHY_IF` sigue en LP11 y el TOP usa en ese par el símbolo de `PHY_CTRL`. El reloj tiene secuencia propia de LP01, LP00, polarización, HS-0, tren de pulsos, HS-0 y LP11. `READY` anuncia disponibilidad en LP11 antes de la petición; se retira al reservar. `LINK_FSM` no espera `READY` dentro de la línea. Admitir `HS_REQ` solo en la ventana acordada, con el adelanto de CLK ya cumplido; una petición temprana es un error de protocolo, inhibe la ráfaga y exige reset común para rearmar. Una vez reservada, la ventana de CLK sobrevive al descenso de `CLK_REQ` en EOT; no se admite otra línea hasta el retorno seguro. |
| `HS_SERIALIZER` | Conservar interfaz, registro de slot en `↓CLK_BYTE`, carga en `↑PCLK` y `b0…b7`. Mantener `TRAIL` hasta la retirada efectiva de OE: reservar tres ciclos para la latencia captura→salida además de cuatro ciclos útiles de trail. No usar el vencimiento del contador de EOT de `LINK_FSM` como señal de OE. |
| `CLOCK_DDR` | Cambio interno: añadir `CLK_TOGGLE` de `PHY_CTRL` y transferirlo con dos registros de 1 bit en `↓PCLK_110`, con borrado asíncrono a 0 usando `RST_LOCAL`. El `OSER4` carga `0101` al alternar y `0000` al parar; solo D0 y D2 cambian. Ambos patrones terminan en bajo, así que el último pulso alto completo termina en el flanco de bajada propio del serializador. El driver permanece habilitado sobre HS-0 antes del primer pulso y después del último. `CLKDIV` y `OSER4` siguen en marcha; conservar el retardo de salida opcional y evitar una compuerta sobre `Q0` o usar `Q1` para aislar. |
| `DPHY_PADS` | Sin cambio funcional. `00` aísla, `01` conduce símbolo LP con el diferencial en Z, `10` conduce `00` por la rama LP y permite el diferencial con su OE; `11` queda reservado. Cambiar de modo con el diferencial apagado. `ISO` domina combinacionalmente los nueve OEN (seis TBUF y tres TLVDS_TBUF). |

La FSM de `PHY_CTRL` decide en `↑CLK_BYTE`; controla por separado las
fases de datos y CLK. En `↓CLK_BYTE` se muestrean `HS_REQ` y `CLK_REQ`
(un bit cada una, a cero en reset), se actualizan temporizadores y se
aplican las salidas de modo y OE. Cada grupo usa un contador de fase
de hasta 5 bits (máximo tramo 27 B), que se carga al entrar en fase,
avanza solo en fases temporizadas y vuelve a cero en `RST_CTRL`. El
estado de cada grupo (4 bits) va a seguro y ambos modos (2 bits por
grupo), OE (1 bit por grupo) y `CLK_TOGGLE` (1 bit) van a cero con
`RST_CTRL=RST_BYTE || !RUN || PROTOCOL_FAULT`, síncrono con el flanco de
cada registro. El datapath conserva la fase anterior de cada grupo
(4 bits, reset a seguro en ↓) para cargar el primer tick. `LP_CLK_PN`
(2 bits) se aplica en ↓, parte de `11` en reset y se prepara en `11`
durante el intervalo aislado del retorno. El error de protocolo se
enclava en 1 bit en ↑, aserta `ISO`, mantiene `RST_CTRL=1`, y solo se
borra en ↑ con `RST_BYTE=1`. No se realimenta al reset de la PLL.
El registro de slot (8 bits) y `LAST_BIT`
(1 bit) son los ya existentes, con reset local activo alto `ISO || RST_BYTE`.

No se cambia `CLK_GEN`; `CLK_REQ` no conmuta `CLK_BYTE` ni `CLK_HS`. Los
caminos `↑→↓` de control y `↓→↑PCLK` de carga son de medio ciclo
(≈9,09 ns nominal para byte). `CLK_TOGGLE` cruza a un reloj relacionado:
comprobar ambas capturas, recuperación/remoción y latencia en todas las
fases de arranque; no ocultar los caminos con una excepción asíncrona.

## Tabla de flancos

Perfil **candidato de simulación**: reloj no continuo por línea,
`B=18,182 ns` (55 MHz), `CLK_HS=220 MHz`, `UI=2,273 ns`,
`LP_DIV=6` (fase LPDT ≈109 ns), `T_LPX/PREP/ZERO/TRAIL=4/3/7/4`,
`C_LINE=1166`. `dN` es el N-ésimo `↓CLK_BYTE` desde el primer
muestreo de `CLK_REQ`; `Pᵢ` es el `↑PCLK` tras el `↓` que captura el
slot `i`. `Fᵢ` es el lanzamiento de su bit 0; cada bit ocupa un UI.
`L(x)` es símbolo LP, `B0` polarización resistiva (`00`), `H(x)` es
diferencial activo y `Z` es driver apagado. Cada celda de un par muestra
**rama LP / rama HS**. Los estados se observan tras propagación.

| Flanco / evento | D0 / D1 | CLK | Control, palabra presentada o consumida |
|---|---|---|---|
| Reposo y LPDT | D0 `L(11 o LPDT)/Z`; D1 `L(11)/Z` | `L(11)/Z` | `READY=1` antes de peticiones; `LOCK` cualificado. En init no se reserva CLK, incluso durante WAIT final. |
| ↑ antes de `d0`; `d0` | Ambos `L(11)/Z` | `L(11)/Z` | `LINK_FSM` acepta línea con `READY && LOCK`, entra en `CLK_PRE`. `d0` muestrea `CLK_REQ`, retira disponibilidad. |
| `d1…d4`; `d5` | Ambos `L(11)/Z` | `L(01)/Z` durante 4 B; luego `L(00)/Z` | Preámbulo de CLK de `PHY_CTRL`, independiente de `PHY_IF`. |
| `d6`; `d7`; `d8` | Ambos `L(11)/Z` | `Z/Z`; `B0/Z`; `B0/H(0)` | Secuencia `01→00→10` de **modo** del adaptador con HS apagado; 1 B de polarización antes del OE. Salida OSER4 en cero antes de habilitar. |
| `d22`; hasta `d25` | Ambos `L(11)/Z` | `B0/H(0)` → `B0/H(CLK)` | `CLK_TOGGLE=1`; dos `↓PCLK_110` transfieren, siguiente `↑` carga `0101`. Primer flanco y primer período íntegro visibles a más tardar en `d25`, condición a verificar. |
| ↑ antes de `d27`; `d27…d30`; `d31` | Ambos `L(01)/Z` durante 4 B; luego `L(00)/Z` | `B0/H(CLK)` | `PHY_IF` publica LP01 en `d27` y LP00 en `d31`. El reloj lleva al menos 2 B activo antes de LP01 de datos. |
| `d32`; `d33`; `d34=z`; `d35=z+1` | `Z/Z`; `B0/Z`; `B0/Z`; `B0/H(0)` | `B0/H(CLK)` | Modo de datos aislado 1 B, luego polarizado 2 B antes de OE. En `z` se muestrea `HS_REQ`; 7 slots ZERO desde `d35`. |
| `d41=↓−1` | `B0/H(0)` | `B0/H(CLK)` | `PHY_IF` publica `B8/B8`; el serializador todavía toma ZERO. |
| `d42=↓0`; `P₀`; `F₀` | Ambos `B0/H(SoT)` desde `F₀` | `B0/H(CLK)` | En `↓0` se consume SoT y `PHY_IF` publica W0 (`3E/70`); `P₀` carga SoT. |
| `d43=↓1` hasta `d1123=↓1081` | `B0/H(W0…W1080)` tras latencia | `B0/H(CLK)` | Consumo de W0 por `↓1`/`P₁`/`F₁=F₀+B`, sin hueco. W1 es `08/13`; W2…W1081 son las 1080 palabras de píxeles. |
| `d1124=↓1082`; ↑ siguiente | `B0/H(W1081)` tras latencia | `B0/H(CLK)` | Se consume último píxel; `PHY_IF` publica W1082 (CRC D0/D1). En ↑ se detecta `PK_DONE`, cae `HS_REQ`. |
| `d1125=↓1083=c`; `P꜀`; `F꜀+7 UI` | Ambos `B0/H(CRC)` tras latencia | `B0/H(CLK)` | WORD todavía captura CRC y guarda `b7` por carril. Último bit real en `F꜀+7 UI`, válido hasta `F꜀+8 UI`. |
| `d1126…d1132` | Tras latencia, `B0/H(~CRC[7])` por carril | `B0/H(CLK)` | Ningún WORD adicional. Desde `F꜀+8 UI`, trail continuo: `0/1` para barras (`EE/7E`); `1/1` para blanco (`25/34`). `CLK_REQ` cae al salir de EOT y `PHY_IF` publica LP11 en `d1130`; la reserva física sigue. |
| `d1133`; `d1134`; `d1135` | `B0/Z`; `Z/Z`; `L(11)/Z` | `B0/H(CLK)` | OE de datos cae tras margen de latencia y trail; conservar polarización 1 B y aislamiento 1 B. `PHY_IF` ya tiene LP11 antes de restaurar el símbolo. Referir post al corte del último carril. |
| `d1144`; hasta `d1147` | Ambos `L(11)/Z` | `B0/H(CLK)` → `B0/H(0)` | Cumplido `T_CLK-POST`, retirar `CLK_TOGGLE`; carga de `0000` tras la transferencia. Última bajada natural, seguida de HS-0. No se retira OE en la misma transición. |
| `d1151`; `d1152`; `d1153` | Ambos `L(11)/Z` | `B0/Z`; `Z/Z`; `L(11)/Z` | Cortar OE de CLK tras el HS-0, conservar polarización 1 B, aislar 1 B y volver a LP11. `READY` se anuncia al concluir la guarda LP11 de 6 B (`d1159`), antes de la siguiente petición. |
| `d1166`; `d1193` | LP11; luego siguiente LP01 | Siguiente reserva; CLK ya activo antes del nuevo LP01 | `d1166` es el siguiente `d0` si hay otra línea disponible; LP01→LP01 = 1166 B. |
| Cualquier instante: `ISO↑` | `Z/Z` | `Z/Z` | Los OEN suben por propagación combinacional aun con ambos relojes parados. Un pulso puede quedar parcial; se descarta la línea y se repite init tras reset común. |

## Comprobaciones de presupuesto

- CLK: LP01 dura 4 B (~72,73 ns); LP00→HS-0 ocupa 3 B
  (~54,55 ns). LP00→inicio de pulsos es al menos 17 B (~309,09 ns);
  el primer período completo debe verse antes de `d25`. Presupuesto de
  transferencia: hasta 2 períodos de 110 MHz, medio período y 4
  períodos de 220 MHz hasta `Q0` (~40,91 ns); 3 B dejan ~13,64 ns
  para un período de salida y retardos. Verificar todos los rearmes
  y la variante con retardo. El margen antes de LP01 de datos es 2 B,
  frente al objetivo `T_CLK-PRE ≥ 8 UI` (~18,18 ns).
- Datos: LP01 dura 4 B; LP00→HS-0 ocupa 4 B (~72,73 ns, dentro de
  40 ns + 4 UI a 85 ns + 6 UI nominales). LP00→SoT es mayor que
  `145 ns + 10 UI`; OE se establece con el pipeline aún en ZERO.
- Drenaje: en el modelo Gowin la latencia `δ8` desde `↓` al primer bit
  es ~31,82–45,46 ns. Presupuestar 3 B (54,55 ns) para ambos carriles,
  incluidos los márgenes que han de comprobarse. En `c+8 B`, el trail
  físico nominal es `7 B − δ8 ≈ 81,81–95,45 ns`, frente a
  `max(8 UI, 60 ns + 4 UI) ≈ 69,09 ns`. Si la latencia real no cabe
  en el presupuesto, no validar este perfil por el contador.
- Reloj: `d1144−d1133=11 B` (200 ns), frente al objetivo
  `T_CLK-POST ≥ 60 ns + 52 UI ≈ 178,18 ns` desde el fin del trail
  de ambos carriles. La última bajada debe haber llegado en `d1147`
  como máximo; hasta `d1151` hay al menos 4 B (~72,73 ns) de HS-0,
  frente a `T_CLK-TRAIL ≥ 60 ns`. Verificar esos intervalos en pads
  incluyendo propagación del OEN, jitter y diferencias entre carriles.
- Línea: `LINK_FSM` reserva `27+4+3+7+1085+4=1130 B`, incluido el
  drenaje lógico, y quedan `35 B` de GAP más `1 B` de `LINE_WAIT`.
  El cierre físico y la guarda ocupan parte del GAP: CLK vuelve a LP11
  en `d1153`, permanece al menos 6 B (~109 ns) antes de `READY`,
  y sobran 7 B hasta la próxima reserva. El período candidato es
  21,20 µs; ningún margen se interpreta como porch medido.

## Aborto, supervisor y validación posterior

- `RESET` de `CLOCK_GEN` es el reset asíncrono de PLL; `RST_BYTE` es el
  reset lógico común. `RST_BYTE` asertado o `LOCK_RAW` bajo alcanza
  `ISO` sin esperar flancos. No realimentar `LOCK`/`!LOCK_RAW` al reset
  de PLL. Al caer `ISO`, la guarda y las fases seguras impiden reactivar
  OE de una ráfaga anterior.
- El supervisor del futuro TOP debe vigilar actividad de la referencia
  **y** de los relojes distribuidos (`CLK_BYTE` y `CLK_HS`), desde
  una base independiente. `LOCK_RAW` alto no prueba actividad. Ante
  pérdida debe asertar y mantener el corte vía `RST_BYTE`, también si no
  hay flancos. Estabilizar referencia, aplicar/liberar el reset físico
  de PLL según fabricante, comprobar actividad y `LOCK_RAW` continuo
  ≥2 ms; sostener `RST_BYTE` durante un `↑` válido y el `↓` siguiente
  antes de liberarlo con setup/hold. Rearmar en reposo con peticiones
  bajas; reiniciar `INIT_SEQUENCER`, packer y fuente. El banco podrá
  emular el supervisor y probar una parada con `LOCK_RAW` retenido.
- El banco reutiliza los estímulos y la comparación de ROM del PR #11,
  con `MIPI_TX`, `INIT_SEQUENCER`, `VIDEO_SOURCE` y PHY reales y solo
  primitivas Gowin modeladas. Reconstruir desde pads: 18 LPDT, todas
  las esperas/WAIT final y END; dos líneas, barras y blanco con `FFFF`
  inyectado solo en banco (1080 lecturas, CRC `25/34` en D0/D1); comprobar
  primer/último pulso de CLK, flancos, separación, aborto sin relojes y
  rearme desde ROM y SoT. Se miden los tiempos desde flancos en los
  pads del modelo.
- Reportar por separado simulación, rutas (PCLK/HCLK de las tres E/S,
  rutas locales y OEN) y auditoría de fusibles en memoria. En PR #17
  Apicula 0.32 falló con `BANK_VCCIO=1.2` en HS y `DRIVE=UNKNOWN`
  en LP; mantener visible el resultado y conservar la auditoría LP.
  Pendientes para el TOP de vídeo: cerrar empaquetado HS, reloj/reset y
  fase/niveles; después integrar backlight y blanco fijo. La línea blanca
  verifica el enlace; el flujo de cuadro que acepte el panel sigue abierto.
