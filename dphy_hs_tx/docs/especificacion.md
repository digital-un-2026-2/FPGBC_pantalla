# Especificación inicial de la PHY HS

Fecha de revisión: 2026-11-08. Estado general **PROPUESTO**.
Esta entrega define responsabilidades y descubre los requisitos pendientes;
no fija compatibilidad con el LCD ni habilita una implementación física.

**Estado actual:** el [secuenciador RTL y sus pruebas](../README.md) implementan
el perfil lógico S320 y la restricción a paquetes pares. Este documento inicial
conserva las propuestas históricas; contrato temporal, datapath y FSM concretan
la versión implementada. La composición de reposo se corrigió para no bloquear
solicitudes LP que esperan grant con busy del puente alto.

**Ampliación:** [contrato temporal](contrato_temporal.md). Concreta perfil de
pruebas, cronograma y dos registros de palabra para el modelo. Donde esta
especificación inicial señala esos puntos como pendientes, consultar esa
ampliación; los pendientes normativos, lane parcial y wrapper físico siguen
abiertos. Las decisiones nuevas permanecen PROPUESTAS.

## 1. Evidencia y fuentes

**DOCUMENTADO en el repositorio**, mediante lectura de fuentes y contratos:

- `dsi_hs_transport/src/dsi_hs_transport.v` y `docs/fsm.md`: una palabra de
  16 bits por posedge válido; sin ready de salida. Primera entrega en el
  posedge siguiente al que observa grant. `hs_done` después de entregar last;
  espera `hs_complete` para aceptar otro paquete.
- `dphy_mode_ctrl/src/dphy_mode_ctrl.v` y README: UC en posedge, datapath en
  negedge; reloj antes de datos, datos antes de parada del reloj. Confirmaciones
  actuales funcionales, sin temporizadores físicos.
- `dsi_lane_packer/README.md`: D0 en [7:0], D1 en [15:8]; keep=01 solo final;
  el byte alto ausente no se transmite. Cada paquete empieza por D0.
- `dsi_hs_transport/TB/hs_transport_link_TB.v`: el receptor actual compara
  palabras; las confirmaciones son contadores del testbench, no una PHY serial.
- `docs/hardware.md`: panel exacto y bitrate pendientes; E/S sin integrar.

Fuentes externas consultadas, **DOCUMENTADO** solo con el alcance indicado:

| ID | Fuente y sección | Evidencia utilizable |
|---|---|---|
| G1 | [Gowin UG289-2.2.1E](https://cdn.gowinsemi.com.cn/UG289E.pdf), §4.3.4, figuras 4-23/24 y tabla 4-31 | OSER8 convierte 8:1; PCLK normalmente FCLK/4; reset asíncrono alto; Q1 controla OEN. |
| G2 | Mismo documento, §3.6.7, tabla 3-7 | TLVDS_TBUF tiene habilitación activa baja. No prueba la configuración eléctrica de esta placa. |
| G3 | [Gowin IPUG948-2.3E, 2026-10-15](https://cdn.gowinsemi.com.cn/IPUG948E.pdf), §4.2, figura 4-2 | Separa PCS/control de PHY/serialización. La red externa se remite a TN100. No reutilizar la numeración de figuras de revisiones anteriores. |
| L1 | [Linux v6.12, phy-core-mipi-dphy.c](https://raw.githubusercontent.com/torvalds/linux/v6.12/drivers/phy/phy-core-mipi-dphy.c), `phy_mipi_dphy_config_validate` | Comprobaciones temporales con referencia a D-PHY v1.2 §6.9. Es evidencia de una implementación, no el texto normativo. |
| L2 | [Linux v6.12, phy-mipi-dphy.h](https://raw.githubusercontent.com/torvalds/linux/v6.12/include/linux/phy/phy-mipi-dphy.h), campos clk_pre/clk_post/hs_prepare | Unidades y puntos de referencia temporales; clk_pre se expresa en UI, los otros dos en ps. |
| A1 | [AMD PG202 v4.3, Example 1](https://docs.amd.com/r/en-US/pg202-mipi-dphy/Example-1-High-Speed-Transmit-from-D-PHY-TX-Master-Side), 2024-12-04 | Distingue aceptación de bytes y retorno a Stop; exige solicitar clock lane para transferir datos. Su ready/latencia pertenecen a esa IP y no se copian a nuestros puertos. |
| A2 | [AMD PG202 v4.3, High Frequency Clock Transmission](https://docs.amd.com/r/en-US/pg202-mipi-dphy/High-Frequency-Clock-Transmission) | Reloj DDR con relación de cuadratura respecto de datos alternantes. No determina la fase de primitivas Gowin. |
| M1 | [MIPI, D-PHY](https://www.mipi.org/specifications/d-phy), apartado Get the Specification | El acceso a las versiones completas se ofrece a miembros. No se obtuvo aquí una especificación normativa completa. |

No se descargan ni redistribuyen PDFs de especificaciones restringidas. No se
ha validado OSER8 sobre los pines concretos ni ejecutado síntesis/P&R de este
bloque. Los resultados de regresión de los README existentes son antecedentes,
no pruebas ejecutadas en esta entrega.

## 2. Responsabilidades propuestas

```text
preparadores → packer → transporte → dphy_hs_tx → modelo serial de prueba
                             ↑          ↕
                         dphy_mode_ctrl

Futuro: dphy_hs_tx → dphy_gowin_io → pads
```

`dphy_hs_tx` ejecutaría preparación/parada y serialización lógica; el árbitro
conservaría propiedad y arbitraje. No duplicar su decisión LP/HS. ECC/CRC y
bytes DSI siguen perteneciendo a los preparadores. Una transacción del
transporte corresponde, provisionalmente, a una ráfaga HS: no se concatenan
paquetes ni se promete vídeo continuo.

El modelo funcional expondría, por lane CLK/D0/D1, estado LP [P,N], bit HS y
habilitación lógica HS. Estas señales permiten observación independiente;
no son voltajes ni controles de pads aprobados. El paso LPDT de D0 pertenece
a la composición con el motor existente: no se debe declarar stop_ready
mientras D0 esté en una operación LP o falten esperas de retorno.

## 3. Interfaz propuesta e integración

| Dirección respecto de PHY | Señales | Regla propuesta |
|---|---|---|
| Entrada | clk, rst | Mismo reloj que transporte/árbitro en el primer arnés; reset cubre ambos flancos del árbitro. |
| Entrada | clk_start_req, data_start_req, data_stop_req, clk_stop_req | Órdenes sostenidas del árbitro; mantener preparación hasta parada/aborto. |
| Salida | clk_prepared, data_prepared, data_stopped, clk_stopped | Confirmar hechos completados; retirar las confirmaciones al iniciar una nueva fase incompatible. |
| Entrada | hs_grant | Observar cuándo el árbitro permite al transporte publicar palabras. No es OE. |
| Entrada | hs_word_data[15:0], hs_word_keep[1:0], hs_word_valid, hs_word_last | Consumir cada posedge válido, sin añadir ready ni modificar el transporte en esta entrega. |
| Entrada | phy_abort | Invalidar operación y suprimir éxito; reset local y recuperación coordinada. |
| Salida | phy_error | Fallo persistente del ejecutor/modelo. Integración propuesta: OR con hs_error del transporte hacia el árbitro; sin lazo combinacional desde phy_abort a phy_error. |
| Salida a composición | reposo local | Combinar con estado/propiedad LP y esperas completas para producir stop_ready al árbitro. |

**Fin de datos y fin físico son distintos.** Se conserva hs_done del transporte
hacia el árbitro. Cuando llega data_stop_req, la PHY termina los bits ya
aceptados antes de iniciar Trail; data_stopped solo se confirma tras el retorno
de ambas data lanes. hs_complete sigue siendo emitido exclusivamente por el
árbitro después del reposo conjunto. No generar un segundo hs_complete.

**Arranque pendiente de cerrar por ciclo:** data_prepared debe garantizar que
la primera palabra del transporte puede capturarse sin perderse, completar
sincronización y empezar los bytes sin un intervalo HS ilegal. El árbitro puede
demorar el grant después del ACK; no emitir un SoT y quedar esperando bytes.
Se propone capturar primero una palabra y lanzar sincronización con una etapa
de almacenamiento justificada por esa latencia. La profundidad, el instante
exacto del ACK y la ventana entre Zero/Sync/primer byte se resolverán en el
diagrama temporal antes del datapath. No afirmar que basta un registro sin
demostrar la ocupación máxima mientras siguen llegando palabras.

## 4. Relojes y temporizaciones

**PROPUESTO:** primer arnés sin CDC entre transporte y árbitro. Un modelo
conductual independiente genera los eventos seriales; no es RTL sintetizable.
Para una palabra de dos bytes por ciclo de reloj de bytes y serialización
8:1: R_lane=8*f_byte, UI=1/R_lane. Con reloj de prueba de 40 MHz resultarían
320 Mb/s por lane; es una deducción del modelo, no una velocidad elegida para
el panel. G1 permite estudiar FCLK=4*PCLK; no se fijan PLL, fase ni constraints.
Un dominio HS distinto de los 40 MHz actuales exigirá diseñar CDC explícito.

Tabla de contraste **DOCUMENTADA en L1**, con tiempos en ns y UI en ns.
No constituye un perfil aprobado ni cubre todos los requisitos D-PHY:

| Intervalo | Comprobación de referencia |
|---|---|
| LPX | ≥50 |
| CLK-PREPARE | 38…95 |
| CLK-PREPARE + CLK-ZERO | ≥300 |
| CLK-PRE | ≥8 UI |
| HS-PREPARE | 40+4 UI … 85+6 UI |
| HS-PREPARE + HS-ZERO | ≥145+10 UI |
| HS-TRAIL, dirección forward | ≥max(8 UI, 60+4 UI) |
| CLK-POST | ≥60+52 UI |
| CLK-TRAIL | ≥60 |
| HS-EXIT | ≥100 |
| EOT | ≤105+12 UI |

No copiar ciegamente los defaults de Linux: su cálculo de Trail adopta n=4,
mientras su validador comprueba el mínimo forward. Las definiciones de los
intervalos se deben cotejar con la versión normativa seleccionada.

**PROPUESTO:** calcular Nmin=ceil(tmin/T) y Nmax=floor(tmax/T) usando la
resolución del evento de salida, incluyendo latencia del serializador. Rechazar
el perfil si Nmin>Nmax; verificar también sumas Prepare+Zero y EOT. La medida
se realiza sobre las transiciones observadas, no sobre el valor del contador.
No asignar todos los tiempos al posedge de 40 MHz por conveniencia.

## 5. Paquetes impares, fallos y límites

`keep=01` no autoriza un byte cero por D1. **PENDIENTE:** documentar terminación
por lane y su compatibilidad DSI/D-PHY, incluido el último bit utilizado para
Trail en la lane que acaba antes. Tampoco se ha cerrado el valor/secuencia de
Sync, orden serial y forma de Trail con referencia normativa suficiente.

**PROPUESTO para un primer modelo restringido:** probar transmisión correcta
con paquetes pares (keep=11); tratar keep=01/00/10 como fallo local antes de
serializar esa palabra. Puede haberse emitido un prefijo: el resultado es
aborto, nunca paquete completo. Esto no implementa el soporte de paquetes
impares del transporte; es una limitación visible hasta cerrar la política.
No se cambia el packer ni se elimina su prueba de paquetes impares.

Detectar falta de valid entre primera y última palabra, datos después de last,
parada antes de last y pérdida de propiedad durante envío. Conservar primera
causa; no esperar que clear_error del árbitro limpie el transporte o la PHY.
Sin reloj/PLL válido no se puede prometer una parada eléctrica temporizada:
la reacción de pads frente a esa situación requiere diseño propio del wrapper.

## 6. Decisiones necesarias antes de RTL

| Decisión | Estado / siguiente evidencia |
|---|---|
| Versión D-PHY y secuencias Sync/Trail/orden de bits | PENDIENTE: referencia normativa aplicable y vectores independientes. |
| Perfil de bitrate y temporización | PENDIENTE: separar perfil sintético de pruebas del perfil real del panel. |
| data_prepared, grant y almacenamiento de arranque | PROPUESTO: cronograma completo y cálculo de ocupación antes de seleccionar registros. |
| Lane parcial | PENDIENTE: política física respaldada; restricción a pares solo propuesta para el modelo inicial. |
| Relojes de integración, fases, CDC y reset OSER | PENDIENTE: modelo de primitivas y validación sobre GW2AR exacta. |
| Tabla eléctrica y composición LP/HS | PENDIENTE: revisar G2, TN100 y hardware real antes del wrapper. |

El siguiente hito es cerrar estas decisiones y el flujo; después justificar
datapath, FSM y pruebas antes de solicitar RTL. Variante LCD y modo de vídeo
bloquean el perfil del panel, pero no la investigación ni un arnés sintético.
