# Diagramas del secuenciador

[Función y contrato](../README.md)

| Archivo | Contenido |
|---|---|
| `SECUENCIADOR_INIT.drawio` | Fuente editable: flujo, datapath y FSM |
| `SECUENCIADOR_INIT.pdf` | Las tres páginas exportadas |
| `flujo.svg`, `datapath.svg`, `fsm.svg` | Vistas consultables desde GitHub |
| [referencias.md](referencias.md) | Revisiones de los drivers usados para contrastar la secuencia |

Describen la lógica implementada, no drivers LP/HS ni funcionamiento probado
en el panel. El contrato RTL prevalece. Los tiempos de alimentación y
preparación son valores de trabajo pendientes de validación física.

Regenerar desde la raíz con Draw.io Desktop y Poppler (no necesarios para
simular); editar primero el `.drawio`:

```sh
drawio -x -f pdf -a --crop --theme light -o secuenciador_init/docs/SECUENCIADOR_INIT.pdf secuenciador_init/docs/SECUENCIADOR_INIT.drawio
pdftocairo -svg -f 1 -l 1 secuenciador_init/docs/SECUENCIADOR_INIT.pdf secuenciador_init/docs/flujo.svg
pdftocairo -svg -f 2 -l 2 secuenciador_init/docs/SECUENCIADOR_INIT.pdf secuenciador_init/docs/datapath.svg
pdftocairo -svg -f 3 -l 3 secuenciador_init/docs/SECUENCIADOR_INIT.pdf secuenciador_init/docs/fsm.svg
```

El paso por PDF conserva los textos como trazos, sin depender de HTML en SVG.
