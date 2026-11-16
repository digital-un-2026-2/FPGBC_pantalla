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
- Se retiraron los arneses LiteX/UART/LiteScope y la prueba de otra placa.
  La nueva integración solo conecta los RTL de inicialización, sin CPU ni UART.

La reproducción está verificada digitalmente; todavía no hay validación del LCD.

## Documentación y pruebas

- [Arquitectura y contrato de implementación](docs/arquitectura.md).
- [Secuencia capturada](docs/secuencia_capturada.md).
- [Hardware y precauciones](docs/hardware.md).
- [Flujo de simulación](docs/flujo_de_trabajo.md).
- [Motor LPDT](motor_lpdt/README.md).
- [Secuenciador](secuenciador_init/README.md).
- [Motor PHY](motor_phy/README.md): flujo, FSM, datapath y RTL lógico.
- [Integración de pads y platform](gateware/README.md).

```sh
pixi run test
pixi run test-init
```

Las pruebas reconstruyen los 18 paquetes desde D0, comprueban ECC/CRC y
miden las esperas completas. No verifican recepción eléctrica del panel.
No se programa la FPGA ni se escribe flash.
