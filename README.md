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
| Implementado | Motor LPDT Verilog de 1–7/15 bytes y secuenciador autónomo de 11 comandos DCS, con ROM y esperas; verificados en simulación |
| Interfaz LP | RTL combinacional con IOBUF/TBUF y top autónomo de los tres bloques; pruebas funcionales con buffers ideales, sin validación eléctrica |
| Integración de depuración | LiteX conecta el motor a registros controlables desde el PC y a LiteScope, un capturador de señales internas |
| Flujo disponible | Simulación, síntesis para FPGBC, carga temporal en FPGA y pruebas internas por UART |
| Pendiente | Constraints y validación física LP, comprobar inicialización en el panel, transmitir imagen en HS e integrar PPU |

**El target de depuración no conecta la salida LPDT al panel.** Una captura
correcta demuestra comportamiento lógico interno, no recepción de la pantalla.

Para sintetizar **secuenciador y motor conectados en un único bitstream** y
capturar ambos con LiteScope, usar el target `debug_init`:
[procedimiento de depuración conjunta](docs/debug_secuenciador_init.md).

## Primera prueba: sin conectar la FPGA

En Linux x86_64, instala [Pixi](https://pixi.sh) y ejecuta desde la raíz:

```sh
pixi install --locked
pixi run test                    # Seis pruebas, incluidos modos de 7 y 15 bytes
pixi run make -C secuenciador_init test-all  # Control y secuencia completa con motor real
pixi run make -C fisical_layer test-all     # Física LP y top integrado; buffers ideales
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
| [secuenciador_init/](secuenciador_init/README.md) | Arranque autónomo Verilog: ROM de comandos, temporizadores, supervisor, pruebas y diagramas |
| [fisical_layer/](fisical_layer/README.md) | Interfaz LP Verilog y `panel_init_top`: secuenciador, motor e I/O conectados; pruebas sin placa |
| [gateware/](gateware/README.md) | Integración LiteX y plataforma FPGBC |
| [scripts/](scripts/README.md) | Herramientas de entorno y prueba interna desde el PC |
| [test/](test/README.md) | Prueba experimental del entorno EDA; no es la regresión LPDT |
| [docs/](docs/README.md) | Arquitectura, procedimientos y hardware |
| `build/` | Archivos generados de LiteX y capturas; no editar ni versionar |
| `pixi.toml`, `pixi.lock` | Comandos y dependencias reproducibles; `.pixi/` y `.toolchain/` son entornos locales ignorados |

Los comandos de los manuales parten de la raíz del repositorio. No ejecutar
`setup-env` o `test-EDA` como preparación automática: el primero modifica el
sistema con `sudo` y el segundo intenta programar un diseño de otra placa.

## Hardware de trabajo

FPGA **GW2AR-LV18EQ144PC8/I7**, reloj de control de **40 MHz** y pantalla
LCD-49754, cuya variante completa sigue pendiente. El reloj de control no es
el reloj de transmisión de alta velocidad. El RESET físico del panel no es
accesible; la secuencia ROM comienza con un comando de reset por DSI.

`fisical_layer/src/panel_init_top.v` conecta `secuenciador_init → motor_lpdt →
fisical_layer`. El camino completo está probado con buffers ideales, no con
el panel. No incluye constraints, PLL ni generador de reset de arranque.
LiteX es un arnés externo de depuración, no una dependencia del arranque autónomo.

No escribir flash ni modificar alimentaciones, resistencias o E/S sin revisión
y autorización. La prueba interna tampoco sustituye la revisión de los pines
no utilizados y de los bancos conectados al panel.
