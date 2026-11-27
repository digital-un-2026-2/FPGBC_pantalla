# FRAME_TIMING

Componente de datapath para el encuadre experimental aprobado en el chat.
Se alojará dentro de `LINK_FSM + TIMER`; **este PR no lo conecta al TOP**.
No cambia el contrato externo de `MIPI_TX`, no genera paquetes ni controla
el PHY, los píxeles o el backlight.

[Diseño y flancos](docs/diseno.md) · [Datapath editable](docs/FRAME_TIMING.drawio)
· [Validación](docs/validacion.md).

## Contrato local

| Puerto | Dirección | Significado |
|---|---|---|
| `CLK_BYTE` | Entrada | Reloj del datapath. |
| `RST_BYTE` | Entrada | Reset síncrono activo alto en ↓; prioridad sobre inicio. |
| `BURST_START` | Entrada | Un ciclo por ráfaga **ya admitida**, estable antes de ↓. |
| `BURST_KIND[1:0]` | Salida | Descriptor registrado de la ráfaga actual: `00` VSS, `01` HSS, `10` RGB; `11` no se emite. |

Cada ↓ con `BURST_START=1` captura el tipo del periodo pendiente y avanza
el índice módulo 743. Sin inicio, índice y descriptor se conservan.
El tipo no cambia en ↑ ni al terminar un paquete. No hay detección de
flanco de `BURST_START`: mantenerlo alto varios ciclos admite varios
periodos y es responsabilidad del consumidor evitarlo.

| Índices, base cero | Tipo | Cantidad |
|---|---|---:|
| 0…2 | VSS | 3 |
| 3…10 | HSS | 8 |
| 11…730 | RGB | 720 |
| 731…742 | HSS | 12 |

Reset lleva el próximo índice a 0 y el descriptor a VSS. Ese descriptor
de reset **no es una petición válida**; solo se usa después de admitir
una ráfaga. La primera admisión tras reset vuelve al periodo 0.

## Pruebas

Desde la raíz:

```sh
pixi run --locked make -C mipi_tx/frame_timing test
pixi run --locked make -C mipi_tx/frame_timing sim
pixi run --locked make -C mipi_tx/frame_timing wave
```

`test` no genera ondas ni abre GTKWave. Ejecuta dos cuadros con
admisiones consecutivas y dos cuadros con separación de 1168 ciclos,
además de pausas, inicio publicado en ↑, retención, fronteras y reset
prioritario en cada transición de tipo y en medio de RGB. `sim` ejecuta
el perfil de 1168 ciclos con `+waves` y abre GTKWave solo tras pasar.
Los productos quedan en `build/frame_timing/`.

Son pruebas unitarias del encuadre: no reconstruyen dos cuadros desde
pads ni validan CRC, temporización física o recepción por el panel.
La integración posterior debe aportar esas verificaciones.

## Evidencia frente a decisión de ensayo

Se midieron 743 periodos de 21,20 µs, 720 intervalos asociados a RGB y
23 verticales con ráfagas breves. No se decodificó esta receta vertical.
**3 VSS → 8 HSS → 720 RGB → 12 HSS es una hipótesis de ensayo**, no una
medición. VSE y EoTp siguen abiertos.

La integración aprobada usará HSS → Blanking de seis ceros → RGB en las
líneas activas. Esos ocho ciclos adicionales desplazan el `READY` de la
base desde `d1159` a `d1167`; se aprobó `C_LINE=1168` a 55 MHz sin
recortar el cierre del CRC, trail ni retención de CLK. Este componente
no contiene temporizador de línea ni modifica ese cierre.
