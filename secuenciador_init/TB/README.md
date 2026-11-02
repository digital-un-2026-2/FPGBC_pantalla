# Pruebas del secuenciador

Desde la raíz:

```sh
pixi run make -C secuenciador_init test
pixi run make -C secuenciador_init test-all
pixi run make -C secuenciador_init sim
pixi run make -C secuenciador_init wave
```

## Control: `secuenciador_control_TB.v`

El testbench modela el datapath en negedge y el handshake del motor en
posedge, con reloj de 40 MHz. Permite sustituir el handshake por estímulos
manuales para provocar errores. Los tiempos se reducen para simular; no son
retardos de inicialización recomendados para el panel.

Comprueba:

- Once descriptores en orden, diez avances, sin envíos duplicados en LISTO.
- Esperas posteriores de cero y tres ciclos, con salida N+1 ciclos después
  del posedge que inicia el reset del temporizador, según la FSM.
- Estabilización y reposo inicial nulos y no nulos.
- Preparación LP y aceptación retrasadas.
- Timeouts de preparación, aceptación y transmisión; descriptor inválido.
- Pérdida LP en cada estado desde REPOSO_INICIAL hasta LISTO.
- Todas las combinaciones de handshake inválidas en SOLICITAR y TRANSMITIR,
  y aceptación inesperada en los demás estados supervisados.
- Prioridad de errores simultáneos y de eventos válidos sobre timeout.
- Primera causa enclavada, captura única y anulación de habilitaciones en FALLO.
- Reset prioritario en los quince estados y una secuencia completa posterior.
- Ausencia de X en controles, reset/incremento excluyentes y estabilidad
  de las salidas al capturar el datapath en negedge.

Las discrepancias y timeouts terminan con `$fatal`. Los resultados `.out` y
`.vcd` se generan en `build/secuenciador_init/`, ignorado por Git.

La vista `secuenciador_init/waves/secuenciador_control_TB.gtkw` agrupa FSM,
descriptor, temporizador, handshake, fallos, estímulos y comprobaciones.
`sim` regenera la simulación y abre esa vista; `wave` abre las ondas existentes.
`state_name` muestra el estado en ASCII bajo `BENCH`, activado por el Makefile.
La vista conserva también `state` en decimal.

Esta es una prueba del control: no instancia las ROM ni el motor LPDT real,
no reconstruye D0, no comprueba ECC/CRC ni los retardos DCS de la ROM real.
Tampoco verifica timing físico, drivers, recepción del panel o integración LiteX.
`pixi run test` mantiene la regresión del motor separada de esta prueba.

## Integración: `secuenciador_init_TB.v`

`pixi run make -C secuenciador_init test TARGET=secuenciador_init` instancia
ambos tops reales: secuenciador y motor LPDT con ancho 4. Comprueba:

- Los 11 paquetes, incluido el de 15 bytes, reconstruidos desde D0 ciclo a ciclo.
- Selector `87`, orden LSB, Escape, Mark/Space de 100 ns y retorno a LP-11.
- ECC recalculado y CRC de payload con semilla `FFFF`, polinomio reflejado `8408`.
- Longitudes, WC, orden de descriptores y esperas DCS completas: 285 ms.
- `terminado` posterior a LP-11, ausencia de duplicados y pérdida LP en LISTO.
- Reset inicial y reset posterior al fallo.

Solo acorta estabilización, reposo inicial y timeout de preparación; no los
delays DCS. `test` no vuelca ondas; `sim TARGET=secuenciador_init` genera FST
y abre GTKWave. La reconstrucción depende de los tiempos conocidos: no es
un receptor LPDT general ni detecta glitches entre muestras.

Faltan inyecciones con ambos tops reales: reset/pérdida LP durante transmisión,
timeouts, aceptación retrasada y secuencia completa después de recuperar reset.
El contrato y los parámetros están en [el README del secuenciador](../README.md).
