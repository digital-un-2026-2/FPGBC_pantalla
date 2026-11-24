# Diagramas del secuenciador

[Función y contrato](../README.md)

| Archivo | Contenido |
|---|---|
| `SECUENCIADOR_INIT.drawio` | Fuente editable: flujo, datapath y FSM |
| `SECUENCIADOR_INIT.pdf` | Las tres páginas exportadas |
| `flujo.svg`, `datapath.svg`, `fsm.svg` | Vistas consultables desde GitHub |
| [referencias.md](referencias.md) | Revisiones de los drivers usados para contrastar la secuencia |

**Son diagramas históricos de la secuencia de 11 comandos.** No reflejan
el paso de 5 bits, los descriptores de 36 bits, la ROM de 204 bytes ni las
esperas actuales. No certifican drivers LP/HS ni recepción del panel.
Para el diseño vigente prevalecen el RTL y
[la arquitectura LP](../../docs/arquitectura.md).

Regenerar desde la raíz con Draw.io Desktop y Poppler (no necesarios para
simular); editar primero el `.drawio`:

```sh
drawio -x -f pdf -a --crop --theme light -o secuenciador_init/docs/SECUENCIADOR_INIT.pdf secuenciador_init/docs/SECUENCIADOR_INIT.drawio
pdftocairo -svg -f 1 -l 1 secuenciador_init/docs/SECUENCIADOR_INIT.pdf secuenciador_init/docs/flujo.svg
pdftocairo -svg -f 2 -l 2 secuenciador_init/docs/SECUENCIADOR_INIT.pdf secuenciador_init/docs/datapath.svg
pdftocairo -svg -f 3 -l 3 secuenciador_init/docs/SECUENCIADOR_INIT.pdf secuenciador_init/docs/fsm.svg
```

El paso por PDF conserva los textos como trazos, sin depender de HTML en SVG.
