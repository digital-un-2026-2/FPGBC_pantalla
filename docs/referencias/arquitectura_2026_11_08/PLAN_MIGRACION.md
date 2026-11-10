# Plan de migración incremental y puertas de aceptación

No modificar `main` masivamente. Cada etapa es una rama/PR pequeña, con límites claros, revisión y rollback. Las etapas posteriores dependen de las evidencias anteriores. Codex debe enumerar diferencias entre diseño objetivo y código existente antes de tocar un módulo.

## Fase 0 — Congelar y auditar el baseline (PR documental)

1. `git status`, `git log`, árbol de archivos; inventario de fuentes, testbenches, herramientas y relojes. Identificar **rutas y líneas** reales de módulos legados.
2. Ejecutar si hay herramientas disponibles: `make -C motor_lpdt test`, `make -C motor_lpdt test-all`; documentar salida, versiones Icarus/Make y limitaciones. Opcional `pixi run test` si el manifiesto existe y el entorno puede instalarse.
3. Graficar dependencias y registrar el contrato real de `motor_lpdt`: `clk`, `rst`, `permiso_arranque`, `solicitud`, `cantidad_bytes[2:0]`, `pos[2:0]`, `byte_almacen[7:0]`, `aceptado`, `ocupado`, `terminado`, `estado_D0[1:0]`, conforme a su README pero validado contra RTL.
4. Identificar si `0x87` se genera internamente y qué bytes figuran en el almacén.
5. Auditar bugs/ambigüedades: solicitud sostenida, busy/done, reset, lectura síncrona de `byte_almacen`, caminos de 12.5 ns y temporizadores.
6. Crear/actualizar `docs/INVENTARIO_REAL.md` y ajustar los estados de las decisiones. **No modificar archivos `.v` en esta fase.**

**Gate G0:** baseline definido, tests corridos o impedimento explicado, lista de RTL y timing sin afirmaciones no verificadas.

## Fase 1 — Especificación D-PHY LP y prueba independiente

Entregar solo documentación en este orden: protocolo con cita; algoritmo Escape Entry/Command/Exit; datapath/contadores; FSM con tabla; test plan con un decodificador que observe `estado_D0` y reconstruya bits independiente del DUT. Calcular tiempos en ciclos desde 40 MHz y los mínimos normativos verificables. Revisar conveniencia de un flanco único sin perder semántica legado.

**Gate G1:** contrato y golden vectors aprobados. Sólo por instrucción explícita generar/editar Verilog, módulo por módulo, con regresión del legado.

## Fase 2 — Packetizer DSI corto y Wishbone aislado

Primero escribir especificación y pruebas para DCS short 0x05/0x15, cabecera de cuatro bytes y ECC, con vector inicial del repositorio como referencia de regresión y vectores independientes. Integrar `dsi_lp_packet_tx` a LPDT con transacción sin pérdida ni duplicación. Registrar layout Wishbone propuesto, sin fijar integración LiteX mientras falte entorno real. Firmware maneja esperas.

**Gate G2:** pruebas self-checking, stalls, reset, descriptor inmutable y equivalencia con el primer vector. `DONE` local claramente diferenciado de ACK LCD.

## Fase 3 — Comandos largos sólo según necesidad real

Si la secuencia válida del LCD lo requiere: definir DCS Long 0x39/Generic, WC, buffer de comandos y CRC16 con vectores normativos independientes. Si no requiere long packets, **no implementar todavía**.

**Gate G3:** no hay sobrecoste ni complejidad sin requerimiento.

## Fase 4 — Control de modo y adaptador físico Gowin en simulación

Cerrar diagramas temporales LP11, HS request, CLK/Data separation, HS prepare/zero/trail/exit, resets y arbitraje. Tabla eléctrica por estado y por conductor. Instanciar sólo las primitivas documentadas y válidas para GW2AR, bajo permiso explícito. Separar simulación funcional sin fabricante de wrapper tecnológico. Revisar timing, pines, polaridad de TLVDS_TBUF.OEN, 100 Ω serie y GPIO a cero durante HS según referencia TLVDS.

**Gate G4 (no hardware todavía):** test de exclusión eléctrica, constraints y resultados synthesis/P&R. **Gate HW extra:** autorización/revisión física y mediciones; si no se cumple, permanece deshabilitado.

## Fase 5 — HS serializer y transport de bytes (sin pantalla)

Definir velocidad por lane, estructura de relojes y fases, primitivas OSER8, entrenamiento/SoT y fin de ráfaga con tiempos normativos. Inyectar patrones sintéticos 16 bits/ciclo y reconstruir streams de D0/D1 mediante monitor independiente; comprobar bitrate y timing. Verificar el HS clock lane.

**Gate G5:** continuidades y timing demostrados; sin PPU ni datos de panel supuestos.

## Fase 6 — Vídeo DSI y presupuesto de tasas

Cerrar D-001/002/003/004. Elegir modo según panel exacto, elaborar hoja matemática por línea, eventos, packetizer RGB888, ECC/CRC, distribución bytes y política de underflow/overflow. No introducir FIFOs ni framebuffers sin derivación de profundidad y clock crossing. Validar patrón de cuadro completo en simulación.

**Gate G6:** un frame simulado se reconstruye exactamente con la secuencia de paquetes y lanes acordada, sin stalls HS ilegales.

## Fase 7 — Integración real con SoC y firmware

Auditar fuentes FemtoRV/LiteX/PPU. Implementar CDC justificado, dirección Wishbone, inicialización del panel en firmware (sólo después de conseguir secuencia real), telemetría y guardas de fallo. Mantener firmware/SoC fuera del repositorio si no existe allí; usar contratos y pruebas con mocks hasta disponer del proyecto integrador.

**Gate G7:** comandos desde CPU y vídeo desde PPU verificados de extremo a extremo en simulación/STA.

## Fase 8 — Validación hardware controlada

No programar ni conectar el LCD sin revisión: pin mapping, VCCIO compatible, niveles LP y HS, modo común, amplitud diferencial, corriente, polaridades, simultaneidad de ramas, clock phase, PLL, timing y condiciones de medición. Registrar capturas y tolerancias. Avanzar desde señal estática segura a LP, luego HS y sólo al final secuencia LCD.

**Gate G8:** medición y aprobación explícita de responsables; no declarar conformidad completa D-PHY por una prueba de osciloscopio aislada.

## Formato obligatorio de cada PR

- Objetivo delimitado y decisiones cerradas en este PR.
- Archivos modificados; no mencionar archivos sin inspeccionarlos.
- Fuente técnica con sección/figura cuando corresponda.
- Contratos antes/después, compatibilidad y diagrama.
- Casos de prueba nuevos y resultado exacto (`PASS/FAIL/NO EJECUTADO`).
- Riesgos físicos, CDC y timing (si corresponde).
- Qué queda explícitamente fuera.
- Plan de reversión.

## Criterio de parada

Si falta la variante del LCD, una temporización normativa, una conexión o el modelo de flujo de la PPU, no adivinar. Mantener interfaz independiente y continuar en un bloque cuya especificación sea suficiente. No confundir el éxito de Icarus con síntesis, STA, seguridad eléctrica o compatibilidad con el LCD.
