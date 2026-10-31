# FPGBC_pantalla

Desarrollo de un **host MIPI DSI** para la pantalla de la consola
[FunnyPlaying FPGBC](https://funnyplaying.com/products/fpgbc-kit).
Un host es el emisor: prepara los comandos y la imagen que recibe la pantalla.
DSI es el protocolo usado para transportarlos.

El objetivo es llevar la imagen de una PPU (bloque que produce píxeles) hasta
la pantalla, usando dos canales de datos. **Todavía no es un controlador de
pantalla completo ni eléctricamente validado.**

## Qué funciona y qué falta

| Estado | Contenido |
|---|---|
| Implementado | Motor LPDT en Verilog: convierte paquetes preparados en estados lógicos de baja potencia; pruebas unitarias e integrada |
| Integración de depuración | LiteX conecta el motor a registros controlables desde el PC y a LiteScope, un capturador de señales internas |
| Flujo disponible | Simulación, síntesis para FPGBC, carga temporal en FPGA y pruebas internas por UART |
| Pendiente | Conectar y validar la capa eléctrica, inicializar el panel, transmitir imagen en alta velocidad e integrar PPU/RISC-V |

**El target de depuración no conecta la salida LPDT al panel.** Una captura
correcta demuestra comportamiento lógico interno, no recepción de la pantalla.

## Primera prueba: sin conectar la FPGA

En Linux x86_64, instala [Pixi](https://pixi.sh) y ejecuta desde la raíz:

```sh
pixi install --locked
pixi run test                    # Las cinco pruebas del motor original
pixi run sim                     # Prueba integrada y visor GTKWave
```

Para trabajar con las herramientas directamente:

```sh
pixi shell
# Aquí están disponibles python, iverilog, yosys, etc.
exit                            # Salir del entorno
```

La primera instalación requiere Internet. `pixi.toml` y `pixi.lock` se
versionan; `.pixi/`, las ondas y los resultados de compilación no.

## Qué leer

1. [Arquitectura explicada](docs/arquitectura.md): de la PPU a la pantalla,
   significado de los términos y diferencia entre lo previsto y lo existente.
2. [Flujo de trabajo](docs/flujo_de_trabajo.md): entorno, simulaciones, síntesis,
   carga en SRAM y capturas en FPGA, paso a paso.
3. [Hardware y seguridad](docs/hardware.md): revisar **antes de programar**.
4. [Depuración LiteX](docs/litex_debug.md): registros, supervisor y analizador.

El [índice de documentación](docs/README.md) reúne las referencias detalladas.

## Organización

| Carpeta | Para qué sirve |
|---|---|
| [motor_lpdt/](motor_lpdt/README.md) | Motor Verilog original, contrato de interfaz y pruebas |
| [gateware/](gateware/README.md) | Integración LiteX y plataforma FPGBC |
| [scripts/](scripts/README.md) | Herramientas de entorno y prueba interna desde el PC |
| [test/](test/README.md) | Prueba experimental del entorno EDA; no es la regresión LPDT |
| [docs/](docs/README.md) | Arquitectura, procedimientos y hardware |
| `build/` | Archivos generados de LiteX y capturas; no editar ni versionar |

Los comandos de los manuales parten de la raíz del repositorio. No ejecutar
`setup-env` o `test-EDA` como preparación automática: el primero modifica el
sistema con `sudo` y el segundo intenta programar un diseño de otra placa.

## Hardware de trabajo

FPGA **GW2AR-LV18EQ144PC8/I7**, reloj de control de **40 MHz** y pantalla
LCD-49754, cuya variante completa sigue pendiente. El reloj de control no es
el reloj de transmisión de alta velocidad. El RESET físico del panel no es
accesible; se prevé un comando de reset por DSI.

No escribir flash ni modificar alimentaciones, resistencias o E/S sin revisión
y autorización. La prueba interna tampoco sustituye la revisión de los pines
no utilizados y de los bancos conectados al panel.
