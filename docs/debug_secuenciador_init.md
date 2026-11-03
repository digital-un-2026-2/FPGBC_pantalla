# Depuración conjunta del secuenciador y motor

Target independiente: `gateware.targets.debug_init`. No modifica el target
`debug` del motor ni exporta señales al panel. Solo reloj y UART usan pines.

## Flujo, datapath y control del arnés

```text
Arranque FPGA → reset interno → secuenciador autónomo → 11 paquetes → LISTO
PC: reset local=1 → elegir paquete → armar LiteScope → reset local=0
    → esperar captura y LISTO/FALLO → descargar ondas y marcas de ciclo
```

```text
CSR reset_prueba ── OR reset sys ──→ secuenciador_init
                                      │ rst_motor
CSR lp_habilitada AND preparar_lp ──→  │                  motor_lpdt (4 bits)
                                      ├── solicitud/permiso/longitud/byte →│
                                      └──────── aceptado/ocupado/fin/pos ←┘
                                                          │
                    monitor pasivo: contador 32 bits + 11 pares inicio/fin
                                                          │
           CSR de estado/marcas ←──────────────────────────┤
           LiteScope ← handshake, D0, datos, índice, trigger seleccionado
```

No se añade FSM funcional. El monitor cuenta aceptaciones y finales (saturación
en 15 y error persistente si hay más de 11 o handshake incoherente), conserva
las primeras 11 marcas y la primera finalización de inicialización. Su contador
se congela en LISTO/FALLO; las cuentas siguen vigilando duplicados hasta reset.
El índice de captura es el número de transmisiones terminadas, no un nuevo
puerto del RTL del secuenciador. CSR y monitor usan posedge; el RTL conserva
sus dos flancos. No se registra el camino combinacional ROM → motor.

`lp_habilitada=1` por defecto simula exclusivamente la disponibilidad interna:
`lp_preparada = preparar_lp AND lp_habilitada`. No representa drivers físicos.
`reset_prueba=0` por defecto conserva arranque autónomo al configurar. El PC
mantiene reset durante accesos UART para incluir ambos flancos y armar la captura.
El reset local no reinicia UART, CSR o LiteScope. Un fallo requiere reset, sin
reintentos automáticos. El reset del motor incluye `rst_motor` del secuenciador.

## CSR del banco `init`

Direcciones siempre desde el `csr.csv` generado, no constantes del cliente.

| Nombre del cliente | Acceso | Contenido |
|---|---|---|
| `init_reset_prueba` | RW | Reset local por nivel; default 0 |
| `init_lp_habilitada` | RW | Preparación LP simulada; default 1 |
| `init_paquete` | RW | Índice 0–10 para trigger (11–15 no disparan) |
| `init_estado` | RO | bit 0 en curso, 1 completa, 2 fallo, 5:3 causa, 6 error monitor |
| `init_cuentas` | RO | 3:0 aceptaciones, 7:4 finales; esperado `BB` hexadecimal |
| `init_inicio0` … `init_inicio10` | RO | Ciclo del pulso aceptado, muestreado en posedge |
| `init_fin0` … `init_fin10` | RO | Ciclo del pulso terminado, muestreado en posedge |
| `init_completa_ciclo` | RO | Primera observación de init_completa |

Marcas de 32 bits desde la liberación de reset local. Se conservan hasta reset.
El estado completo normal es `02` hexadecimal, sin causa ni error. Las lecturas
de marcas no forman un snapshot atómico durante el arranque: leerlas en LISTO.
Un envío espurio posterior incrementa cuentas/activa error aunque el contador
de tiempo ya esté congelado.

## Estrategia de captura

2048 muestras a 40 MHz no cubren las esperas largas. Se repite el arranque
completo 11 veces, seleccionando un paquete distinto en cada ejecución. Cada
ejecución registra además los 11 inicios/finales y el ciclo de LISTO; así las
esperas se verifican dentro de una misma ejecución, nunca con tiempos del PC.
La ventana puede incluir paquetes consecutivos sin espera; el verificador
delimita el paquete seleccionado por su aceptación y su final, sin confundir
las transacciones vecinas. Las marcas completas detectan envíos adicionales.

Esperas y parámetros de arranque son los originales. Fallo, timeout, captura
incompleta, cuentas incorrectas o discrepancias de bytes/tiempos impiden PASS.
Las ondas se conservan antes de verificarlas. El resumen incluye hashes del
bitstream y CSV asociados; no demuestra que el usuario cargase esos archivos.

Para este RTL y parámetros exactos, contrastados con la simulación del wrapper:
primer aceptado en ciclo 808009; `fin-inicio = 64×(longitud+1)+21`;
`inicio_siguiente-fin = espera_ROM+8`; `completa-fin_último = 4800000+2`.
Los ciclos adicionales corresponden al control y observación de handshake;
no son modificaciones de las esperas DCS. LISTO se observa en ciclo 12213826
(aproximadamente 305,346 ms desde la liberación de reset).

## Ejecución

```sh
pixi run python -m gateware.targets.debug_init --build
pixi run python -m unittest scripts.test_init_debug -v
# Revisar informes, medio ciclo de 12,5 ns, CST y pines no usados.
# Carga SRAM únicamente con revisión y autorización; nunca flash.
# Abrir litex_server con la UART identificada, a 115200, bind 127.0.0.1.
pixi run python scripts/test_init_hw.py --output-dir build/debug_init/captures/prueba_01
```

Bitstream y mapas: `build/debug_init/gateware/debug_init.fs`,
`build/debug_init/csr.csv`, `build/debug_init/analyzer.csv`. No mezclar con
`build/debug/`. La prueba solo valida lógica interna, no tensiones, D-PHY,
recepción DCS, backlight ni imagen.

Este target usa `timingstrict=True`: no permite que nextpnr continúe tras un
fallo de timing. Esto no añade restricciones de E/S ni valida caminos que la
herramienta no modele; sigue siendo necesario revisar el informe y el circuito.
El CST solo declara reloj/UART (pines 11/28/27). Las doce ramas conectadas al
panel quedan sin recursos solicitados; no interpretar eso como una garantía
de alta impedancia sin pulls. Los defaults/template de Apycula y la situación
de configuración/bancos deben revisarse antes de autorizar una carga.

El cliente deja ambos módulos bajo reset local al terminar (también al fallar,
si el enlace sigue disponible). Para repetir, ejecutar de nuevo la prueba; para
recuperar el arranque autónomo sin cliente basta una nueva configuración/reset
global. No hay cambios en el contrato funcional ni nueva entrada RTL de reinicio.

## Evidencia de esta integración (2026-11-02)

En la rama `feature/debug-secuenciador-init`, sobre `7611ae3` más los cambios
de esta integración, se ejecutaron satisfactoriamente:

- `pixi run test`: las seis pruebas del motor, incluidos anchos 3 y 4.
- `pixi run make -C secuenciador_init test-all`: control y secuencia integrada.
- `pixi run python -m unittest scripts.test_init_debug -v`: tres pruebas;
  monitor, vectores ECC/CRC y wrapper generado con ambos tops reales. Comprueba
  los 11 paquetes, marcas de ciclo, trigger seleccionado, corrupción de datos,
  tiempos erróneos, saturación, reset local, pérdida LP y timeout de preparación.

Los dos primeros bloques RTL no se modificaron. La prueba del wrapper no incluye
el bus UARTWishbone ni el pipeline de LiteScope: esa cobertura requiere capturas
reales adicionales. La prueba no se ejecutó en FPGA: al revisar el equipo no
había programador USB ni puertos `ttyACM`/`ttyUSB` disponibles.

También terminó `pixi run python -m gateware.targets.debug_init --build` con
timing estricto, Yosys 0.69+ y nextpnr 0.11.1. El informe final indica PASS a
40 MHz (Fmax estimada 71,96 MHz); camino crítico negedge→posedge de 6,948 ns,
margen 5,552 ns sobre medio ciclo. El reporte JSON indica 5147 LUT4, 2078 DFF,
5 BSRAM y 3 IOB (las cifras preliminares del log de packing son distintas).
Yosys no encontró problemas en CHECK; avisó del `reg z` con asignación continua
en el comparador existente. No se modificó ese auxiliar en esta integración.

Bitstream local generado: `build/debug_init/gateware/debug_init.fs`, SHA-256
`29a193136ea13b15b4de4227c2ff1977b89fd2e59207e53e3b09595491859aac`.
Bitstream, informes y mapas son productos ignorados, no se versionan. Este
resultado no cierra la revisión de pines no utilizados ni valida eléctricamente
la placa. Se intentó obtener un informe adicional reimportando el JSON ruteado,
pero la herramienta no lo admitió; los valores anteriores corresponden al build
completo original, no a esa reimportación fallida.
