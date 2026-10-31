# Diseños y reloj/reset

[Gateware](../README.md) · [Flujo completo](../../docs/flujo_de_trabajo.md)

Un target reúne bloques, plataforma y opciones para generar un diseño.

| Archivo | Uso |
|---|---|
| `debug.py` | Target principal: SoCMini sin CPU, UARTWishbone, registros, supervisor LPDT y LiteScope |
| `lpdt_demo.py` | Contiene `CRG`, generador de reloj/reset utilizado por `debug.py`, y la clase auxiliar `LPDTDemo` |

`CRG` conecta el reloj de 40 MHz y mantiene el reset durante el arranque mediante
un contador. Reset devuelve la lógica a su estado inicial; no es el RESET físico
de la pantalla. Aunque vive en `lpdt_demo.py`, también lo utiliza `debug.py`.

Desde la raíz, dentro de `pixi shell`:

```sh
python -m gateware.targets.debug
python -m gateware.targets.debug --build
```

La primera orden solo genera; la segunda añade síntesis e implementación.
Ambas escriben `build/debug/` y ninguna programa la FPGA. `lpdt_demo.py` no tiene
una interfaz de build propia. Se conserva porque el target principal importa su `CRG`.

El target añade explícitamente las seis fuentes Verilog del motor y registra
los bancos CSR. La captura LiteScope tiene 2048 muestras a 40 MHz. D0 permanece
interno: no se exportan drivers del panel ni transporte HS.
