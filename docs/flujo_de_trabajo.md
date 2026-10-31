# Flujo de trabajo: de la simulación a la FPGA

[Inicio](../README.md) · [Arquitectura y glosario](arquitectura.md) · [Hardware](hardware.md)

Todos los comandos parten de la **raíz del repositorio**, en Linux x86_64.
Las instrucciones de hardware son para la FPGBC y la conexión confirmada por
el responsable; no deben trasladarse a otra placa sin revisar sus E/S.

## 1. Instalar y activar el entorno

Instala [Pixi](https://pixi.sh). Después:

```sh
pixi install --locked
pixi shell
```

`--locked` instala las versiones registradas en `pixi.lock` sin actualizarlo.
La primera instalación requiere Internet. Dentro de `pixi shell`, las
herramientas se llaman directamente, como `python` o `iverilog`. Para salir:

```sh
exit
```

Como alternativa, `pixi run <comando>` ejecuta una orden dentro del entorno
sin abrir una sesión interactiva. Por ejemplo, `pixi run python -m
gateware.targets.debug` equivale a ejecutar ese módulo desde `pixi shell`.

**En lo que sigue se presupone `pixi shell` activo**, también en cada terminal
adicional. No hace falta el compilador RISC-V para el target `debug`: no usa CPU
ni compila software para ella.

### Comprobar herramientas de síntesis

```sh
command -v python iverilog vvp yosys yowasp-nextpnr-himbaechel-gowin gowin_pack openFPGALoader
command -v nextpnr-himbaechel-gowin
```

La síntesis convierte la descripción en recursos de la FPGA. La implementación
coloca esos recursos y traza sus conexiones. El flujo utiliza Yosys (síntesis),
nextpnr (implementación) y Apycula/`gowin_pack` (empaquetado de la configuración).
YoWASP distribuye una versión portable
de nextpnr. Si existe `yowasp-nextpnr-himbaechel-gowin` pero falta el nombre
`nextpnr-himbaechel-gowin`, crear el enlace **solo dentro del entorno activado**:

```sh
ln -s "$CONDA_PREFIX/bin/yowasp-nextpnr-himbaechel-gowin" \
  "$CONDA_PREFIX/bin/nextpnr-himbaechel-gowin"
```

No ejecutar si el destino ya existe: comprobar primero a qué herramienta apunta.
Este enlace local puede necesitar recrearse al reinstalar el entorno.

**No usar `pixi run setup-env` como paso obligatorio.** Ese script también
descarga un compilador RISC-V y modifica reglas udev del sistema mediante `sudo`.
Consultar [scripts](../scripts/README.md) antes de decidir ejecutarlo.

## 2. Pruebas sin FPGA: motor original

```sh
pixi run test
pixi run make -C motor_lpdt test TARGET=reg
pixi run sim
pixi run wave
```

| Orden | Resultado |
|---|---|
| `test` | Compila y ejecuta las cinco pruebas originales |
| `test TARGET=reg` mediante Make | Prueba solo el registro `reg_0.v` |
| `sim` | Ejecuta la integrada y abre GTKWave |
| `wave` | Abre ondas existentes; no vuelve a ejecutar la prueba |

Los resultados van a `motor_lpdt/build/`. Las vistas `motor_lpdt/waves/*.gtkw`
guardan qué señales mostrar, no sus datos. Los fallos y timeouts de los
testbenches terminan con `$fatal`.

Sin Pixi, con Make e Icarus instalados: `make -C motor_lpdt test-all`.
**`make -C motor_lpdt test` ejecuta solo la integrada**, no las cinco.
Cobertura y límites: [testbenches originales](../motor_lpdt/TB/README.md).

## 3. Alcance de las simulaciones

Las pruebas de `motor_lpdt/TB/` verifican el motor Verilog y sus auxiliares.
No simulan la integración LiteX, el reset de arranque, el supervisor CSR ni el
puente UARTWishbone. No hay actualmente una prueba automatizada de simulación
para esa integración; las capturas internas en FPGA complementan las pruebas
del motor, pero no sustituyen esa cobertura pendiente.

## 4. Generar el diseño y sintetizar

Para generar Verilog y mapas de registros **sin síntesis**:

```sh
python -m gateware.targets.debug
```

Para generar, sintetizar, colocar y conectar el circuito, y producir el bitstream:

```sh
python -m gateware.targets.debug --build
```

**Ninguno de estos comandos programa la FPGA.** El target está definido en
`gateware/targets/debug.py`; la plataforma fija el reloj a 40 MHz.

| Archivo generado | Uso |
|---|---|
| `build/debug/gateware/debug.v` | Circuito generado a partir de la integración Python |
| `build/debug/gateware/debug.cst` | Asignaciones de pines y estándares de E/S |
| `build/debug/gateware/debug.rpt` | Informe de síntesis Yosys |
| `build/debug/gateware/debug.report` | Informe de implementación y timing de nextpnr |
| `build/debug/gateware/build_debug.sh` | Órdenes de herramientas generadas por LiteX |
| `build/debug/gateware/debug.fs` | Bitstream que se carga en la FPGA |
| `build/debug/csr.csv` | Direcciones de registros para el cliente del PC |
| `build/debug/analyzer.csv` | Nombres, anchuras y configuración de señales LiteScope |

Regenerar puede sobrescribir los archivos anteriores. No editar los resultados
para cambiar el circuito: modificar sus fuentes y volver a generar.
**Conservar juntos el bitstream y sus dos CSV.** Generar nuevos CSV sin cargar
el nuevo bitstream deja al cliente describiendo un circuito distinto.

### Antes de cargar: revisión obligatoria

1. Leer [hardware y seguridad](hardware.md); confirmar placa, programador y cableado.
2. Revisar `debug.cst`, estándares de E/S, pines no usados y bancos del panel.
   Que D0 no se exporte no garantiza por sí solo un estado eléctrico seguro
   de todos los pines no utilizados.
3. Revisar advertencias e informes de síntesis e implementación.
4. Comprobar timing a 40 MHz, especialmente caminos posedge→negedge y
   negedge→posedge: disponen de medio ciclo, **12,5 ns**, no de 25 ns.
   Revisar también el almacén de bytes hacia el motor y caminos sin restricción.
5. Inspeccionar el script generado: el flujo observado incluye
   `--timing-allow-fail`. **Que exista `debug.fs` o termine el build no basta
   para declarar el timing correcto.**

## 5. Cargar temporalmente en la FPGA

**Esta orden sí modifica el circuito activo de la FPGA.** Ejecutarla únicamente
con revisión y autorización. El siguiente ejemplo es la conexión usada por el
responsable: FT232RL, asignación `TXD:CTS:RTS:RXD`, reloj de programación de 1 MHz.
Los pines cambian según programador y cableado; no copiar esa asignación a ciegas.

```sh
openFPGALoader \
  --cable ft232RL \
  --pins TXD:CTS:RTS:RXD \
  --freq 1000000 \
  --write-sram \
  --bitstream build/debug/gateware/debug.fs
```

`--write-sram` carga la memoria temporal de configuración, **no escribe flash**.
Al perder alimentación se pierde esta configuración; el comportamiento del
próximo arranque depende de lo que ya tenga la placa en su memoria de arranque.
El 1 MHz de programación no sustituye el reloj de control de 40 MHz.

No usar `test-EDA` como alternativa: apunta a una Tang Nano 9K e incluye carga
automática. Ver [prueba experimental de entorno](../test/README.md).

## 6. Abrir la comunicación de depuración

La programación y la UART de depuración son funciones diferentes. El comando
anterior configura la FPGA; el servidor siguiente permite acceder a sus registros.
No abre un enlace DSI con la pantalla.

Para identificar dispositivos serie conectados:

```sh
ls /dev/serial/by-id/
ls /dev/ttyACM* /dev/ttyUSB*
```

Algunas rutas pueden no existir. Identificar el adaptador correcto por su nombre
estable o por los cambios al conectarlo. `/dev/ttyACM2` es el puerto usado por el
responsable, **no un nombre fijo del proyecto**. Evitar otro programa usando
simultáneamente el mismo puerto.

En una terminal con `pixi shell` activo:

```sh
litex_server \
  --uart \
  --uart-port /dev/ttyACM2 \
  --uart-baudrate 115200 \
  --bind-ip 127.0.0.1
```

Mantenerla abierta. El servidor conecta la UART de la FPGA con un puerto de red
local (1234 por defecto), al que se conectan los scripts. `127.0.0.1` limita
el acceso al propio PC. Detener con `Ctrl+C` cuando ya no haya clientes.

## 7. Capturar y verificar el motor en FPGA

En **otra terminal**, desde la raíz y con `pixi shell` activo:

```sh
python scripts/test_lpdt_hw.py \
  --output build/debug/captures/patron_01.vcd
```

La prueba actual prepara siete bytes (`00 FF 55 AA 12 34 A5`), arma LiteScope,
solicita el envío, descarga ondas y comprueba handshake, estados, tiempos y bytes.
El selector `87` lo añade el motor. **La salida sigue siendo interna.**

Elegir un destino nuevo en cada ejecución: el script no sobrescribe capturas.
Aunque el destino predeterminado del código se llame `tres_bytes.vcd`, el patrón
actual es de siete bytes; por eso aquí se usa un nombre explícito.

```sh
gtkwave build/debug/captures/patron_01.vcd
python scripts/test_lpdt_hw.py --help
```

Opciones útiles: `--host`, `--port`, `--csr-csv`, `--analyzer-csv` y `--timeout`.
Los valores predeterminados esperan los CSV de `build/debug/` y el servidor local.

### Secuencia DCS interna

```sh
python scripts/test_lpdt_hw.py \
  --dcs-sequence \
  --reset-wait-ms 0 \
  --sleepout-wait-ms 0 \
  --output-dir build/debug/captures/dcs_01
```

Genera tres capturas y `summary.json`: Software Reset (`05 01 00 10`),
Exit Sleep (`05 11 00 36`) y Display On (`05 29 00 1C`). Calcula el ECC en el
PC y comprueba que el motor devuelve los mismos paquetes, precedidos por `87`.

**Los ceros son solo para esta prueba interna sin conexión al panel.** No son
temporizaciones recomendadas de inicialización. Las esperas son pausas adicionales
del PC después de descargar y verificar cada captura, no medidas exactas entre
comandos sobre D-PHY. Las esperas reales y la secuencia del panel siguen pendientes.

## 8. Qué se considera verificado

| Nivel | Qué demuestra | Qué no demuestra |
|---|---|---|
| Testbenches originales | Comportamiento lógico del RTL en los casos cubiertos | Circuito colocado o señales eléctricas |
| Build e informes revisados | Implementación y timing de esa configuración | Compatibilidad eléctrica del panel |
| Captura interna correcta | Estados y datos muestreados dentro de la FPGA | Recepción, ejecución DCS o imagen visible |

Existen artefactos locales de implementación y un resumen de secuencia interna
con `PASS`. No identifican por sí solos la revisión exacta probada. Para resultados
reproducibles registrar: commit y cambios locales, comando, versión de herramientas,
placa/conexión, bitstream y CSV asociados, resultado y límites de la prueba.
Los artefactos se guardan fuera de Git; una conclusión relevante debe resumirse
en documentación, no depender de que otro usuario tenga el mismo `build/`.

## 9. Problemas frecuentes

| Síntoma | Qué revisar |
|---|---|
| Falta un módulo Python | Entorno activado y `pixi install --locked` completado |
| No se encuentra nextpnr | Nombre esperado y enlace local del apartado 1 |
| No se encuentra `debug.fs` | Se ejecutó `--build`, no solo generación; revisar el fallo de herramientas |
| Permiso denegado en USB/serie | Permisos y reglas udev apropiadas al adaptador; no resolver ejecutando todo como root |
| No abre la UART | Puerto correcto, conexión y ausencia de otro proceso usándolo |
| Timeout de acceso o captura | Bitstream correcto, reloj, UART a 115200, servidor y CSV correspondientes |
| Señales ausentes o layout distinto | `analyzer.csv` y nombres fijos en `SIGNALS` del script; no renombrar el CSV para ocultar el problema |
| El destino ya existe | Elegir otro `--output` o `--output-dir`; conservar la captura anterior |
| Build correcto, dudas de timing | Revisar informes y `--timing-allow-fail`; no interpretar el código de salida como cierre temporal |

`pixi run test` no programa nada. `python -m gateware.targets.debug --build`
tampoco. `openFPGALoader --write-sram ...` y `test-EDA` **sí intentan cargar hardware**.
