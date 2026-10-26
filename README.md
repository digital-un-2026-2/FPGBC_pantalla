# FPGBC_pantalla

Desarrollo de un **host MIPI DSI de dos lanes de datos** para la pantalla de
una consola [FunnyPlaying FPGBC](https://funnyplaying.com/products/fpgbc-kit),
reutilizando la solución eléctrica de su placa.

## Estado

- Motor LPDT en Verilog: control, datapath y testbenches unitarios e integrado.
- Vector inicial: `87 05 01 00 10` (selector LPDT + paquete DSI Software Reset).
- Simulación con Icarus Verilog y vistas de señales para GTKWave.
- Pendientes: validación eléctrica, inicialización del panel, transmisión HS
  e integración con PPU y RISC-V.

**No es todavía un host DSI completo ni un controlador validado en la pantalla.**
Una simulación correcta no demuestra conformidad D-PHY ni recepción del panel.

## Inicio rápido

Necesitas `make` e Icarus Verilog (`iverilog`, `vvp`); para ver ondas, `gtkwave`.
Desde la raíz:

```sh
make -C motor_lpdt test            # Compilar y ejecutar la prueba integrada
make -C motor_lpdt sim             # Ejecutar y abrir GTKWave
make -C motor_lpdt test-all        # Ejecutar todas las pruebas del módulo
```

Los `.out` y `.vcd` se generan en `motor_lpdt/build/` y no se versionan. Los `.gtkw`
de `motor_lpdt/waves/` sí: guardan la vista, no los datos. Tras clonar, `sim` genera
las ondas y carga la vista correspondiente.

## Organización

| Ruta | Contenido |
|---|---|
| [motor_lpdt/](motor_lpdt/README.md) | Fuentes, pruebas, ondas y documentación del motor |
| [docs/hardware.md](docs/hardware.md) | Conexiones, medidas y precauciones |
| [docs/arquitectura.md](docs/arquitectura.md) | Arquitectura prevista y pendientes |

Cada módulo tendrá su propia carpeta; DSI, PHY y demás bloques se añadirán
cuando comience su desarrollo. Los [diagramas del motor](motor_lpdt/README.md#diagramas)
se pueden consultar directamente en GitHub.

## Hardware de trabajo

FPGA Gowin GW2AR en EQ144 según identificación del usuario; pantalla LCD-49754,
con variante completa pendiente. El periférico dispone de **40 MHz**; no es el
reloj HS. El RESET físico del panel no es accesible y se prevé reset por DCS.

No programar la FPGA ni modificar alimentaciones, resistencias o configuración
eléctrica sin revisar las E/S y contar con autorización del responsable.
