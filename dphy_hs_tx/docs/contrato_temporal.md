# Contrato temporal del modelo HS

**PROPUESTO, 2026-11-08.** Desarrollo del contrato inicial. Resuelve un modelo
funcional de prueba, sin autorizar RTL ni elegir el perfil del LCD.

## Referencias nuevas

- **G4, DOCUMENTADO:** [Gowin IPUG112-2.02E](https://www.gowinsemi.com/upload/database_doc/277/document/5d36810e104f6.pdf),
  §6.2, figuras 6-2/6-3: muestra 00→B8→bytes por lane; la interfaz 8:1
  utiliza un reloj de bytes cuatro veces menor que el reloj HS. Esto no
  determina las latencias de un wrapper propio.
- **T1, DOCUMENTADO:** [Lattice FPGA-IPUG-02080-1.6](https://www.latticesemi.com/-/media/LatticeSemi/Documents/UserManuals/IPUGs/FPGA-IPUG-02080-1-6-CSI2-DSI-DPHY-Tx-IP-Core-Radiant-SW.ashx?document_id=52453),
  §3.4, figura 3.5: Sync B8 por lane y Trail derivado invirtiendo el último
  bit válido. No copiar los puertos o latencias de esa IP.
- **T2, DOCUMENTADO:** [Lattice FPGA-IPUG-02080-2.6](https://www.latticesemi.com/-/media/LatticeSemi/Documents/UserManuals/EI2/FPGA-IPUG-02080-2-6-CSI2-DSI-DPHY-Tx-IP-User-Guide.ashx?document_id=52453),
  §2.6.4, figura 2.21 y §8: contempla bytes no alineados mediante controles
  específicos y advierte sobre Trail/EOT en varias lanes. No prueba la
  equivalencia de esos controles con nuestro keep.

L1/L2 del [contrato inicial](especificacion.md) proporcionan la tabla de
contraste de tiempos. Las ecuaciones siguientes son **deducciones de diseño**.
La fuente normativa completa y el perfil real del LCD siguen pendientes.

## Perfil sintético S320

Reloj compartido de transporte, árbitro y lógica de bytes: 40 MHz, T=25 ns.
Dos lanes, 8 bits/lane/ciclo: R_lane=320 Mb/s, UI=3,125 ns.
En el modelo ideal, cada bit dura UI y el receptor muestrea en el centro del
bit. El reloj diferencial tiene periodo 2 UI; los cambios de datos se sitúan
a UI/2 del siguiente flanco de muestreo. El generador conductual produce
estos eventos; no se propone sintetizar lógica con retardos `#`.

| Intervalo de salida | Ciclos de 25 ns | Duración | Contraste con L1 |
|---|---:|---:|---|
| Reposo inicial del modelo | 4000 | 100 µs | init≥100 µs; no es reset del panel |
| LPX | 2 | 50 ns | ≥50 |
| CLK-PREPARE | 2 | 50 ns | 38…95 |
| CLK-ZERO | 10 | 250 ns | Prepare+Zero=300 |
| CLK-PRE | 1 | 25 ns | ≥8 UI=25 |
| HS-PREPARE | 3 | 75 ns | 52,5…103,75 |
| HS-ZERO mínimo | 5 | 125 ns | Prepare+Zero=200≥176,25 |
| Sync de prueba | 1 | 25 ns | B8 por lane según G4/T1 |
| HS-TRAIL | 3 | 75 ns | ≥72,5; EOT ideal=75≤142,5 |
| CLK-POST | 9 | 225 ns | ≥222,5 |
| CLK-TRAIL | 3 | 75 ns | ≥60; EOT ideal≤142,5 |
| Exit, por lane | 4 | 100 ns | ≥100 |

Los tiempos son **del modelo ideal**, sin latencia de pad ni de OSER8.
No transferir estos contadores al wrapper sin medir la latencia real.
Sync B8 se serializa provisionalmente LSB primero: 0,0,0,1,1,1,0,1.
Esta elección permite un vector de pruebas; su condición normativa permanece
pendiente de cotejo. Trail de datos se propone constante al complemento del
último bit serial de esa lane; Trail de CLK permanece HS-0.

## Arranque sin depender de una llegada inmediata de grant

1. Completar CLK-PREPARE/ZERO, iniciar reloj, cumplir PRE y levantar
   clk_prepared. Sostener reloj hasta terminar POST y Trail.
2. Completar HS-PREPARE y el mínimo HS-ZERO; levantar data_prepared y mantener
   HS-0. No lanzar Sync aún. Esta espera adicional en Zero es una hipótesis
   explícita del modelo: no se hereda de la tabla de mínimos como prueba de
   ausencia de otras restricciones normativas.
3. El árbitro recibe el ACK y hs_data_ready. Concede el enlace. El transporte
   observa grant y después publica su primera palabra.
4. Al capturar la primera palabra, empezar Sync durante un periodo T. En el
   siguiente posedge, empezar la serialización de esa palabra sin hueco.

El primer evento serial ocurre después del flanco de captura en el orden de
eventos del modelo, sin leer entradas que cambien en el mismo delta de simulación.
La prueba debe demorar grant y ACK; Sync nunca precede a la captura inicial.

## Cronograma con RTL existente

A es el posedge donde la UC del árbitro observa data_prepared y
hs_data_ready. La tabla supone señales estables antes del flanco y muestra
los efectos posteriores a él. Se deduce de mode_control/mode_datapath y
hs_transport_control, no de las latencias de una IP comercial.

| Flanco | Árbitro | Transporte / PHY |
|---|---|---|
| A | Entra HS_TRANSFER; grant sube combinacionalmente | Transporte aún observa el grant anterior bajo |
| A+1 | Mantiene grant | Transporte observa grant y entra SEND; valid sube después del flanco |
| C0=A+2 | Mantiene grant | PHY captura W0 en PENDING; emite Sync durante [C0,C1) |
| C1 | Mantiene grant salvo paquete de una palabra | ACTIVE←W0; captura W1 si existe; serializa W0 durante [C1,C2) |
| Ci, 1≤i<N | Mantiene grant hasta fin de entrada | ACTIVE←W(i−1); PENDING←Wi; sin burbujas |
| C(N−1) | Aún grant | Captura W(N−1), last=1; transporte levanta hs_done después del flanco |
| CN | Observa hs_done; entra HS_DATA_STOP, retira grant y solicita parada | Carga la palabra final en ACTIVE y la serializa durante [CN,C(N+1)) |
| C(N+1) | Espera data_stopped | Termina último bit; inicia Trail porque data_stop_req ya está presente |

N=1: C0 captura la única palabra y emite Sync; C1 retira grant y emite esa
palabra; C2 inicia Trail. Los renglones generales que comparten flanco se
interpretan simultáneamente, no como pasos extra.

**No exigir hs_grant durante el drenaje.** La pérdida de grant solo es error
mientras todavía se espera una palabra antes de last. Al aceptar last se
cierra la entrada; queda prohibido aceptar palabras adicionales.
Una parada antes de aceptar last es error. La ausencia de parada al acabar
el último bit también se trata como error del contrato del modelo; no
prolongar arbitrariamente el último bit mientras se espera la orden.

## Almacenamiento mínimo para este calendario

Dos registros de datos de 16 bits: PENDING conserva la siguiente palabra;
ACTIVE mantiene estable la palabra que se serializa. Cada registro conserva
su marca last y validez; la máscara se valida en la captura de entrada.
Para el modelo restringido a keep=11 no hace falta guardar keep.

- [C0,C1): una palabra pendiente, Sync sale de una constante.
- [Ci,C(i+1)), 1≤i<N: una palabra activa y una pendiente.
- [CN,C(N+1)): solo la última palabra activa.

Cada frontera mueve el valor **anterior** de PENDING a ACTIVE y captura la
nueva entrada en PENDING. El almacenamiento máximo es dos palabras en total;
una FIFO adicional no está justificada por este calendario. Se requiere un
índice serial 0…7 y recuerdo del último bit por lane para Trail; su realización
es parte del siguiente datapath. No aplicar esta cuenta al OSER8 real sin
incorporar su latencia y registros internos.

El [datapath propuesto](datapath.md) concreta esa memoria: el recuerdo del
último bit se obtiene de A_DATA retenido durante Trail, sin registro TAIL
adicional. El índice serial pertenece al generador conductual de simulación.

## Parada y composición con LP

Al acabar los bits, iniciar Trail por 75 ns y después LP-11. Mantener Exit por
100 ns antes de levantar data_stopped. El contador POST se referencia al final
de Trail de la última data lane; puede avanzar mientras se cumple Exit.
Cuando llega clk_stop_req, esperar el remanente de POST si lo hay antes de
parar CLK. No copiar clk_start_req directamente a su habilitación.

Tras CLK-TRAIL y CLK-EXIT, levantar clk_stopped. En la composición propuesta:
stop_ready = reposo_CLK_D0_D1 && !lp_grant && (lp_D0==LP11).
No usar busy del puente para bloquear el reposo: también está alto mientras
espera grant y causaría bloqueo circular. lp_grant cubre la operación física
hasta su fin; la recuperación tras aborto exige reset coordinado de la ruta LP. Las confirmaciones de retorno pueden
mantenerse hasta la siguiente orden de arranque, que las invalida.

El fallo persistente phy_error solo se registra por causas locales; no se
registra automáticamente al recibir phy_abort. El OR hacia hs_error no debe
crear lazo ni convertir reset en un fallo persistente. Tras un fallo hacen
falta resets coordinados; clear_error del árbitro por sí solo no recupera
productores/transporte/PHY.

## Lane parcial y alcance que permanece abierto

La política física completa de keep=01 permanece **PENDIENTE**. T2 muestra que
existen soluciones con controles por lane, pero no demuestra la política
de nuestro enlace. No añadir relleno DSI por D1 ni sostener su último bit
como si fuera un byte nuevo. Se conserva la propuesta inicial: el primer
modelo solo completa paquetes pares y aborta una palabra parcial antes de
serializarla; un prefijo emitido no se cuenta como paquete completo.

Quedan para diseño físico: PLL, CLKOP/CLKOS, fase IOLOGIC, mapeo D0…D7 de
OSER8, reset asíncrono de primitivas y sincronización de su liberación,
respuesta a pérdida de reloj, banco/pads y revisión eléctrica. El modelo
comparte clk entre los tres bloques; no introduce CDC ni respalda conexión
al panel. También quedan pendientes el cotejo normativo de Sync/Trail/orden
de bits y la espera en Zero. Esos límites no bloquean revisar este calendario.

## Comprobación reproducible

```sh
python dphy_hs_tx/docs/verificar_contrato.py
```

El cálculo comprueba con fracciones exactas el perfil S320, las ocupaciones y
el drenaje para diferentes longitudes. Es una comprobación de especificación,
no una simulación RTL de la PHY ni una validación de fuentes normativas.

El [arnés de contrato existente](../TB/contrato_existente_TB.v) conecta el
árbitro y el transporte reales, con ACK funcional inmediato de preparación y
parada de datos demorada. Comprueba primera captura un ciclo después de
observar grant, parada/retirada de grant un ciclo después de last y una sola
operación completa. Resultado ejecutado: **PASS**, N=1/2/3/2048. No mide
latencias de una PHY ni prueba el generador serial aún inexistente.

Reproducción desde la raíz, comandos consecutivos:

```sh
pixi run --locked iverilog -g2012 -s dphy_hs_contract_TB -o /tmp/dphy_hs_contract_sim dphy_hs_tx/TB/contrato_existente_TB.v dsi_hs_transport/src/*.v dphy_mode_ctrl/src/*.v
pixi run --locked vvp /tmp/dphy_hs_contract_sim
```
