# Diagramas de motor_phy

[Contrato propuesto](../README.md)

| Archivo | Contenido |
|---|---|
| `MOTOR_PHY.drawio` | Tres páginas editables: flujo de operaciones, datapath detallado y FSM |
| `MOTOR_PHY.pdf` | Las tres páginas exportadas |
| `flujo.svg` | Flujo de preparación, servicio y aborto |
| `datapath.svg` | Contador, comparador, MUX, concatenación, máscara y buffers |
| `fsm.svg` | Estados circulares con controles de salida y transiciones |

**El RTL lógico de `../src/` implementa estos diagramas. No hay validación
eléctrica todavía; el adaptador de pads se implementa en `../../gateware/`.**
Las exportaciones conservan los
rótulos originales de diseño propuesto.
No representa un receptor, transmisor HS ni detector de tensión.

Se siguen las convenciones de `motor_lpdt` y `secuenciador_init`:

- Flujo: cajas de operaciones, rombos de decisión, flechas Sí/No y contexto externo.
- Datapath sin rellenos de color: bloques y puertos explícitos, anchuras,
  RST/INC, MUX 2:1 y flag `Z_T` hacia la FSM.
- FSM: estados circulares con nombre, separador y valores de control;
  guardas en las flechas y reglas globales de reset/fallo.
- `←` significa asignación; `==` comparación. Las señales iguales se conectan
  por nombre entre páginas, sin inventar registros intermedios.

Regenerar desde la raíz con Draw.io Desktop y Poppler:

```sh
drawio -x -f pdf -a --crop --theme light -o motor_phy/docs/MOTOR_PHY.pdf motor_phy/docs/MOTOR_PHY.drawio
pdftocairo -svg -f 1 -l 1 motor_phy/docs/MOTOR_PHY.pdf motor_phy/docs/flujo.svg
pdftocairo -svg -f 2 -l 2 motor_phy/docs/MOTOR_PHY.pdf motor_phy/docs/datapath.svg
pdftocairo -svg -f 3 -l 3 motor_phy/docs/MOTOR_PHY.pdf motor_phy/docs/fsm.svg
```

El paso por PDF convierte los textos en trazos SVG, como en los otros módulos,
y evita depender de fuentes o `foreignObject` en los visores.
Editar primero el `.drawio`; no retocar las exportaciones a mano.
