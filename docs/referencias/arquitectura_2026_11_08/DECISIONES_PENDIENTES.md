# Registro de decisiones de arquitectura (ADR / bloqueos)

**Nunca cambiar un `PENDIENTE` a `CONFIRMADO` sólo porque el código compila o una IA lo supone.** En `Fuente` debe haber una referencia exacta, y en `Prueba` evidencia reproducible. Los valores de ejemplo son sólo escenarios de cálculo.

| ID | Prioridad | Decisión | Estado al 2026-11-08 | Qué hace falta | Consecuencia de no resolver |
|---|---|---|---|---|---|
| D-001 | Bloqueante | Variante/controlador real LCD-49754 | PENDIENTE | Marcaje exacto, esquema/BOM verificable o trazas/datasheet del módulo instalado | No escoger init ni timing del LCD |
| D-002 | Bloqueante | Modo DSI requerido y formato de sincronización | PENDIENTE | Fuente del panel real: Video Mode (burst/non-burst/etc.) o Command Mode y requisitos de paquetes | No implementar secuenciador HS final |
| D-003 | Alta | FPS, h/v porches, blanking y temporización | PENDIENTE | Datasheet del panel real y viabilidad del flujo PPU | No fijar tasas HS/PLL |
| D-004 | Alta | R_lane y límite real con GW2AR+OSER8 | PENDIENTE | Presupuesto por línea, timing y P&R en dispositivo exacto | No declarar rendimiento factible |
| D-005 | Bloqueante HW | Topología GPIO LP/TLVDS HS y OEN/OE reales | PROPUESTA DOCUMENTADA | IPUG112/948 + UG289 + constraints + síntesis + medición | Prohibido activar pads en placa |
| D-006 | Bloqueante HW | Discrepancia VCCIO LP ~1.21 V vs ~1.30 V | CONFLICTO DOCUMENTAL | Repetir medida bajo condiciones documentadas; cotejar DS226/UG229 | No afirmar tolerancia LVCMOS12 |
| D-007 | Alta | Refactor del motor posedge/negedge LPDT | PENDIENTE | Inspeccionar RTL, simular regressions y STA; definir nuevo contrato | Riesgo de pérdida de funcionalidad o timing |
| D-008 | Alta | Semántica de bytes `0x87` en motor legado | PENDIENTE AUDITORÍA | Ver flujo RTL y testbenches: quién inyecta selector y quién presenta payload | Riesgo de doble Escape Command |
| D-009 | Alta | Requisitos de paquetes de inicialización | PENDIENTE | Script/comandos auténticos para LCD real; si exige Generic Long, etc. | No implementar generic por conjetura |
| D-010 | Alta | Interfaz real de la PPU y backpressure | PENDIENTE | Fuentes del SoC y temporización de píxeles; viabilidad de detener flujo | No dimensionar FIFO/underflow |
| D-011 | Alta | Dominios de reloj y PLL disponibles | PENDIENTE | Integración Litex/Gowin real, netlist/clock tree, limitaciones IOLOGIC | No crear reloj HS arbitrario |
| D-012 | Alta | Profundidad/ubicación FIFO y política underflow | PENDIENTE | Curvas de producción/consumo y presupuesto de bursts; recursos disponibles | No añadir buffers automáticos |
| D-013 | Media | Mapa Wishbone/base address | PROPUESTA | SoC LiteX y firmware existentes; definir byte enables, ACK, reset, IRQ | No adoptar direcciones ilustrativas como finales |
| D-014 | Alta | Capacidad de TX-only sin BTA/RX | ALCANCE ELEGIDO | Ver si la inicialización del LCD exige recepción/ACK/read/BTA | Si lo exige, alcance incompatible |
| D-015 | Alta | Reset físico LCD inaccesible | CONFIRMADO POR USUARIO | Sin asignación de pad; decidir sólo reset interno + DCS | DCS no recupera estados físicos arbitrarios |
| D-016 | Media | Política HS clock continua/no continua | PENDIENTE | Datasheet del panel y tiempos de la PHY | No fijar FSM clock lane final |
| D-017 | Media | Código de error y observabilidad | PROPUESTA | Contrato WB/firmware; pruebas de fallo | Diagnóstico ambiguo |
| D-018 | Alta | Uso de referencia zoatel | MATERIAL DE ESTUDIO | Comparar interfaz y licencia; no importar IP indiscriminadamente | Riesgo de incompatibilidad/licencia |
| D-019 | Alta | Verificación de pinout/pares exactos de EQ144P | PENDIENTE AUDITORÍA | UG115/UG229, Gowin EDA, medición continuidad de la placa | No generar/usar constraints físicos definitivos |
| D-020 | Bloqueante HW | Criterio de autorización de ensayos con panel | PENDIENTE | Revisión eléctrica, instrumentación y autorización responsable | No conectar ni encender HS |

## ADR-001 — Mantener el legado mientras se refactoriza

- **Decisión propuesta:** preservar `motor_lpdt/` y todas sus pruebas. Crear RTL nuevo bajo `rtl/` sólo después de que sus contratos se aprueben.
- **Rationale:** README y motor_lpdt/README documentan contratos temporales y semántica de transacción que pueden perderse con una sustitución masiva.
- **Validación:** `make -C motor_lpdt test-all` y `test` antes y después de cualquier cambio, según herramientas disponibles. Los comandos están documentados; **no fueron ejecutados en esta auditoría externa**.
- **Reversión:** si falla la nueva ruta, el legado sigue siendo baseline intacto.

## ADR-002 — Separación de bytes DSI y Escape LPDT

- **Decisión propuesta:** `dsi_lp_packet_tx` emite bytes `[Data ID][...][ECC]` y, si corresponde, payload/CRC; `dphy_lpdt_tx` emite el comando Escape físico 0x87.
- **Rationale:** evita acoplar protocolo DSI a codificación D-PHY y evita enviar dos veces 0x87.
- **Bloqueante:** verificar cómo entrega bytes el motor legado y su testbench; no renombrar señales por conveniencia.

## ADR-003 — Un solo dueño de pads y permisos

- **Decisión propuesta:** `dphy_mode_ctrl` concede y temporiza; `dphy_gowin_io` aplica lógica eléctrica validada; ningún packetizer toca OE/OEN/pines.
- **Rationale:** la topología usa físicamente ramas LP y HS sobre cada conductor y el orden clock/data HS importa (IPUG112/948 §4.2).
- **Bloqueante:** tabla eléctrica de todas las combinaciones y evidencia de primitivas, pinout y voltajes.

## ADR-004 — No congelar vídeo antes de identificar panel

- **Decisión propuesta:** conservar interfaces abstractas de PPU y estructura HS, pero bloquear codificación final de sincronismos/porches/bitrate.
- **Rationale:** 720×720 RGB888 sólo determina payload activo, no forma de transmitirlo ni presupuesto real.
- **Criterio para cerrar:** evidencia de la variante exacta, modo/frecuencia, y un análisis por línea incluyendo overhead.

## ADR-005 — No inventar reset LCD

- **Decisión:** sin salida de reset física; reset RTL y comando DCS Software Reset son mecanismos diferentes. `DONE` en TX no asegura que el LCD aceptó o ejecutó el comando.
- **Bloqueante potencial:** si el controlador requiere reset por pad para su operación, dejar explícita la incompatibilidad.

## Campos obligatorios al cerrar una decisión

`Fecha | Autor/revisor | Estado anterior/nuevo | Hecho respaldado | Fuente concreta y sección | Impacto en interfaz/datapath/FSM | Prueba reproducible | Alternativas rechazadas | Condición de reversión`.
