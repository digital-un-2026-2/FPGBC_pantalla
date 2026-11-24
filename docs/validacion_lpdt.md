# Validación de la inicialización LPDT en placa

## Objetivo y referencia

Reproducir únicamente la inicialización LPDT, capturar los seis conductores
con el mismo analizador y corregir las diferencias hasta validar la secuencia.
No implementar vídeo ni habilitar transmisores HS en esta prueba.

Referencia principal: `MIPI_DSI.kvdat`.

- SHA-256: `3dd920ef4d1f3bb6493952bc9a1b774746324546bcde99afbfb3ef0877a7e855`.
- 50 MS/s, resolución de 20 ns, duración de 4 s.
- Umbral registrado: 0,90 V. Conservar la misma configuración y cableado
  en las capturas de la FPGA; documentar cualquier cambio.
- CH0=D0P, CH1=D0N, CH2=D1P, CH3=D1N, CH4=CLK_P, CH5=CLK_N.

Los 18 paquetes, incluido el selector `87`, coinciden byte por byte con
`LP_MIPI_DSI.kvdat` y con la secuencia documentada en
[secuencia capturada](secuencia_capturada.md). No es necesario sustituir
los bytes de la ROM para usar esta referencia.

## Ventana de comandos y actividad previa

En `MIPI_DSI.kvdat`:

- Primer comando: entrada Escape a **582,26188 ms**.
- Último comando: entrada Escape a **847,61930 ms**, regreso a LP11
  a **847,63492 ms**.
- D1 y CLK permanecen en LP11 durante los 18 comandos.
- Hay actividad anterior: subida inicial de los tres pares alrededor de
  200 ms, estados `01` alrededor de 481,486–481,493 ms y una entrada
  Escape corta en D0 a 482,26124 ms. Esta última **no contiene un paquete
  DSI con selector `87`** y no se cuenta entre los 18 comandos.

El RTL actual mantiene D1/CLK en LP11 una vez habilitado y no reproduce
esa actividad previa. Su espera inicial tampoco reproduce los tiempos
absolutos del archivo. Por tanto, coincidencia de los 18 paquetes **no**
significa coincidencia de todo el arranque de los seis canales.
No copiar automáticamente los pulsos breves observados como si fueran
comandos adicionales.

## Iteraciones

1. Exportar la variante activa del top `fpgbc_lp_init`, que integra
   secuenciador, ROM de comandos/descriptores, motor LPDT y PHY LP.
   Usar una carpeta nueva por iteración; no reutilizar bitstreams antiguos.
2. Sintetizar y enrutar a 40 MHz. Auditar netlist, pads y fusibles.
   Empaquetar solamente con `scripts/pack_lp_checked.py`.
   Estas comprobaciones no son una medida eléctrica ni programan la placa.
3. Revisar las condiciones de carga de [hardware](hardware.md).
   Acordar el procedimiento de programación antes de conectar/cargar;
   no escribir flash como parte automática del flujo.
4. Armar el analizador **antes del arranque de la FPGA**: el top ejecuta la
   secuencia una sola vez por reset. Con la variante con botón, también se
   puede armar la captura y después pulsar/soltar el centro de volumen
   (pin FPGA 120) para reiniciar la secuencia sin reconfigurar.
   Capturar el arranque, los 18 paquetes completos
   y al menos 10 ms después del último paquete, en los seis canales.
   Una captura de 1 s con pretrigger adecuado cubre la referencia LP;
   conservar 4 s si se desea repetir toda la adquisición original.
5. Guardar cada medición sin sobrescribir la referencia, por ejemplo:
   `captures/lpdt_01.kvdat`. Registrar el hash del bitstream utilizado,
   método de carga/arranque, tasa de muestreo y umbral.
6. Comparar y corregir; repetir síntesis y captura tras cada cambio.

## Criterios de comparación

- **Contenido:** exactamente 18 paquetes, en el mismo orden, mismos bytes
  de selector, cabecera, ECC, payload y CRC; sin paquetes extra ni truncados.
- **Forma de onda D0:** entrada Escape, orden de bits LSB primero, símbolos,
  salida de Escape y vuelta a LP11.
- **Tiempos:** duración de símbolos/ráfagas, pausas entre paquetes y deriva
  acumulada. Alinear ambas capturas por la entrada del primer comando,
  no por el comienzo del archivo. Registrar los errores en ns/µs y declarar
  la tolerancia antes de dar la comparación por aprobada, teniendo en cuenta
  los 20 ns del analizador y los 25 ns del reloj FPGA.
- **Otros cuatro canales:** D1P/D1N y CLK_P/CLK_N en LP11 durante toda la
  ventana de comandos; no basta con decodificar D0.
- **Arranque previo:** comparar por separado la actividad anterior al primer
  comando y el retardo de arranque. No ocultar estas diferencias al alinear.
- **Final:** mantenerse en LP11; no reproducir la actividad posterior de vídeo.

Una simulación correcta, síntesis sin errores o bitstream generado no
constituyen aprobación de la salida física. La validación queda pendiente
hasta disponer de la nueva captura de los seis canales.

## Primera iteración offline

Directorio: `build/lpdt_iteration_01/`, variante activa `--enable-lp`.

- Comparación de las dos capturas y ROM: 18 paquetes / 204 bytes DSI iguales.
- Simulación del top: tres pruebas correctas, incluidos paquetes desde pads,
  pausas completas, abortos y variante aislada.
- Síntesis Yosys: terminada; `check` informa cero problemas. Advierte sobre
  `reg z` asignado mediante `assign` en `motor_lpdt/src/comp.v`.
- Place-and-route: terminado, pasa a 40 MHz; Fmax interna informada
  **88,54 MHz**, sin validación temporal externa.
- Auditorías de netlist sintetizada/enrutada y mapa de E/S: correctas;
  las seis ramas HS tienen salida permanentemente deshabilitada.
- Auditoría de fusibles en memoria: `PAD_FUSE_CHECKS_PASS`; no se escribió
  bitstream en esta iteración.

Se utilizó el ejecutable instalado `yowasp-nextpnr-himbaechel-gowin`
para el enrutado, no el nombre `nextpnr-himbaechel` del shell autogenerado.
No se ha programado hardware ni obtenido una captura de la FPGA.

## Segunda iteración: botón de reset

Directorio separado: `build/lpdt_iteration_02_reset/`.
La primera iteración no tenía una entrada de botón; generar otro `.fs`
desde su JSON no añade el reset.

Se incorpora `global_rst_n` del proyecto vecino
`FPGBC_digital_UN/soc/FPGBC_unal_platform.py`: pulsador central de volumen,
pin 120, activo bajo, LVCMOS33, pull-up. Reinicia secuenciador, motor y PHY;
al soltarlo se repiten la espera inicial y los comandos desde el paso 0.
No cambia alimentación ni RESET físico del LCD.

Verificación: simulación del botón durante transmisión, salida de fallo y
reinicio desde LISTO correctos; los 18 paquetes siguen siendo correctos.
Síntesis, enrutado a 40 MHz y auditorías de pads/fusibles correctos.
Se generó `build/lpdt_iteration_02_reset/fpgbc_lp_init.fs` sin acceder a hardware.
SHA-256: `686b1d0573a6d494bc49c291d4acd2c16fabc493b552fe6f43e2c5eab10cf4b3`.
Pendiente comprobar el pulsador y las señales sobre la placa real.

La captura física posterior `LP_ITERATION_2.kvdat` y la nueva referencia
de tres canales se comparan en
[comparación completa de niveles LP](comparacion_LP_ITERATION_2.md).
Los paquetes coinciden, pero el arranque y las duraciones todavía no.
