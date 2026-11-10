# Integración digital con LiteX

[Inicio](../README.md) · [Arquitectura](../docs/arquitectura.md) · [Flujo completo](../docs/flujo_de_trabajo.md)

Gateware es el circuito que se configura en la FPGA. Aquí se describe en Python
con Migen/LiteX y se conecta al núcleo Verilog de `dphy_lpdt_tx/src/`. Este Python
genera hardware; no necesita una CPU ejecutándolo dentro de la FPGA.

| Carpeta | Responsabilidad |
|---|---|
| [cores/](cores/README.md) | Bloques: wrapper del motor, supervisor y registros de diagnóstico |
| [platforms/](platforms/README.md) | Modelo de FPGA, reloj y asignación física de pines |
| [targets/](targets/README.md) | Diseños completos que reúnen los bloques |

Desde la raíz, dentro de `pixi shell`:

```sh
python -m gateware.targets.debug          # Generar, sin sintetizar
python -m gateware.targets.debug --build  # Sintetizar e implementar, sin cargar
```

Los resultados van a `build/debug/`, no a esta carpeta. El target principal
permite leer/escribir registros por UART y capturar señales con LiteScope.
No incorpora CPU ni conecta D0 al panel. Para revisar informes, programar en
SRAM y probar la FPGA, seguir el [manual de trabajo](../docs/flujo_de_trabajo.md).

## Cadena de pantalla integrada

El target `gateware.targets.display` añade el planificador, generador de franjas,
rutas LP/HS, wrapper Gowin y control CSR por UARTWishbone. Sus pads permanecen
internos; el perfil de panel y la caracterización física siguen pendientes.
[Uso y comprobaciones](../dsi_display/README.md).
