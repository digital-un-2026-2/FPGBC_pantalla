# Inicialización LP de la pantalla FPGBC

Objetivo: transmitir autónomamente los **18 paquetes DSI y sus esperas**
extraídos de `LP_MIPI_DSI.kvdat`, sin CPU, UART ni vídeo HS.

## Arquitectura

```text
clk40 + reset
      │
      ▼
secuenciador_init ◄── ROM de descriptores (base, longitud, espera)
      │                         │
      │ solicitud / longitud    ▼
      ├─────────────────── ROM de paquetes
      │                         │ byte solicitado por pos
      ▼                         ▼
                    motor_lpdt
                         │ estado_D0 = {P,N}
                         ▼
                 interfaz física LP
                         │
                     D0P / D0N
```

El motor devuelve `aceptado`, `ocupado` y `terminado` al secuenciador.
La interfaz física debe confirmar su preparación antes de autorizar el envío.
Al terminar la secuencia se mantiene LP-11; **no se entra a HS**.

## Estado real

- Secuenciador adaptado a los **18 paquetes capturados**: 204 bytes en ROM,
  con cabeceras, ECC, payload y CRC exactos.
- Longitud, posición e índice de paso de **5 bits**. Paquetes de hasta
  **22 bytes DSI**, sin contar el selector `87`.
- Motor parametrizable verificado con `ANCHO_LONGITUD=3`, `4` y `5`
  (1–7, 1–15 y 1–31 bytes, respectivamente).
- Esperas nominales posteriores de **9 ms y 65 ms** a 40 MHz.
  El control añade 225 ns entre ráfagas; después del último paquete no hay
  espera adicional programada.
- PHY lógico y [top de integración LiteX/Migen](gateware/README.md) implementados;
  buffers Gowin y restricciones candidatos, sin validación eléctrica.
- Botón de reset global y auditorías offline de pads y fusibles implementados;
  las seis ramas HS permanecen deshabilitadas.
- Se retiraron los arneses LiteX/UART/LiteScope y la prueba de otra placa.
  La nueva integración solo conecta los RTL de inicialización, sin CPU ni UART.

La reproducción está verificada digitalmente. La comparación de la captura
física de la iteración 2 confirma los bytes de los 18 paquetes, pero quedan
diferencias de arranque y temporización; no hay validación de recepción del LCD.

## Documentación y pruebas

- [Arquitectura y contrato de implementación](docs/arquitectura.md).
- [Secuencia capturada](docs/secuencia_capturada.md).
- [Hardware y precauciones](docs/hardware.md).
- [Flujo de simulación](docs/flujo_de_trabajo.md).
- [Validación LPDT en placa por captura de seis canales](docs/validacion_lpdt.md).
- [Comparación de la captura de la iteración 2](docs/comparacion_LP_ITERATION_2.md).
- [Auditoría de E/S y fusibles](docs/revision_io_lp.md).
- [Herramientas de comparación y empaquetado LP](scripts/README.md).
- [Motor LPDT](motor_lpdt/README.md).
- [Secuenciador](secuenciador_init/README.md).
- [Motor PHY](motor_phy/README.md): flujo, FSM, datapath y RTL lógico.
- [Integración de pads y platform](gateware/README.md).

```sh
pixi run test
pixi run test-init
pixi run test-phy
pixi run test-gateware
pixi run test-captures
```

Las pruebas reconstruyen los 18 paquetes desde D0, comprueban ECC/CRC y
miden las esperas completas. No verifican recepción eléctrica del panel.
No se programa la FPGA ni se escribe flash.

Las capturas `.kvdat` se conservan localmente y están ignoradas por Git.
La ROM y las pruebas contienen los bytes de referencia necesarios para
simular sin esos archivos. Solo el comparador de capturas requiere aportarlos.
Los productos de síntesis, simulación y empaquetado tampoco se versionan.
