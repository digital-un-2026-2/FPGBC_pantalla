# Diseño de FRAME_TIMING

Diseño aprobado antes de escribir RTL y bancos. Referencia fija:
`MIPI_LCD/Docs/MIPI_TX_componentes.pdf` y `MIPI_TX_adopcion.md` en el
repositorio vecino. La ampliación aprobada mantiene los cuatro bloques
de `MIPI_TX` y sus interfaces externas; el encuadre es un componente
interno nuevo de `LINK_FSM + TIMER`.

## Datapath, sin FSM

[Fuente editable](FRAME_TIMING.drawio). Solo se requiere esta vista:
el módulo captura un descriptor y cuenta admisiones, no secuencia fases.

```text
                   FRAME_TIMING
          ┌────────────────────────────────────────────┐
          │                                            │
          │ FRAME_TIMING_COUNT    FRAME_TIMING_KIND     │
START ───►│ EN: contador ↓   ────► rangos combinacionales│
          │ NEXT_PERIOD[9:0]      + descriptor ↓       ├──► BURST_KIND[1:0]
          │ 0…742, módulo 743     EN: BURST_START       │
          └────────────────────────────────────────────┘
```

`CLK_BYTE`, `RST_BYTE` y `BURST_START` llegan a ambos componentes.
El TOP solo los conecta; el contador y el selector registrado tienen
responsabilidades y archivos propios.

| Registro | Bits | Reloj | Habilitación | Reset |
|---|---:|---|---|---|
| `NEXT_PERIOD` | 10 | ↓ `CLK_BYTE` | `BURST_START=1` | `RST_BYTE=1`, síncrono ↓, valor 0 |
| `BURST_KIND` | 2 | ↓ `CLK_BYTE` | `BURST_START=1` | `RST_BYTE=1`, síncrono ↓, valor VSS (`00`) |

Decodificación combinacional del índice **anterior** al flanco:

- 0…2 → `00` (VSS).
- 3…10 y 731…742 → `01` (HSS).
- 11…730 → `10` (RGB).

Ambos registros usan asignaciones no bloqueantes. Por ello, el avance
del contador no cambia el índice que captura el selector en ese ↓.
El descriptor queda retenido toda la ráfaga aunque el índice siguiente
pertenezca a otro tipo.

## Intercambio con LINK_FSM y tabla de flancos

En la integración prevista, `LINK_FSM` admite en ↑ solo desde
`LINE_WAIT`, con `READY && LOCK && VID_REQ && VID_LINE_RDY` y sin
`INIT_REQ` prioritario. Al entrar en `CLK_PRE`, su marca `ENTER_T`
produce combinacionalmente `BURST_START`; dura hasta el ↑ siguiente.
No se deriva de `VID_RD`, `PK_DONE` ni de una oferta no aceptada.

| Evento | Entrada / estado previo | Efecto |
|---|---|---|
| ↓ con reset | Cualquier índice; incluso `BURST_START=1` | Índice 0 y tipo VSS; reset gana. |
| ↑ de admisión | `LINE_WAIT` acepta y entra en `CLK_PRE` | Se publica `BURST_START=1`; aún no cambia el datapath. |
| Primer ↓ de `CLK_PRE` (`d0`) | Inicio alto; índice `n` | Captura tipo de `n`; índice pasa a `n+1`, o a 0 desde 742. |
| ↑ siguiente | Se retira la marca de entrada | `BURST_START=0`; tipo no cambia. |
| ↓ sin inicio | Ráfaga/espera en curso | Conserva ambos registros. |
| ↓ de admisión del periodo 742 | Índice 742 | Tipo HSS; próximo índice 0. |
| ↓ de admisión siguiente | Índice 0 | Tipo VSS; inicia el siguiente cuadro. |

El camino de control ↑→↓ dispone de medio ciclo de byte
(≈9,09 ns a 55 MHz). El descriptor registrado se decodifica en controles
combinacionales para el paquete mucho después de `d0`; no se usa su
valor anterior en el mismo flanco que lo captura. La integración debe
verificar esos caminos, no esconderlos con excepciones asíncronas.

No hay reset de transacción independiente: `BURST_START` avanza el
cuadro, nunca lo reinicia. Ante aborto se requiere reset común para
volver al periodo 0, a la fuente RGB en dirección 0 y a la ROM LP en 0.
El reset del sistema debe cubrir ↑ y ↓ por los módulos vecinos;
este componente solo lo consume en ↓.

## Límites de esta entrega

- No cambia `VIDEO_SOURCE`, `HS_PACKER`, `LINK_FSM`, `PHY` ni el target.
- No demuestra el presupuesto de línea ampliado mediante simulación.
- No genera `.fs` ni habilita salidas físicas.
- El PR del módulo permanece separado del PR de integración.
  La integración debe partir de `main` cuando se integre esta dependencia;
  no se fusiona automáticamente ningún PR.
