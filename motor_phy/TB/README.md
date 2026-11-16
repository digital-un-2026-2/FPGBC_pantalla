# Pruebas de motor_phy

`make -C motor_phy test-all` ejecuta `motor_phy_TB.v` para N=1, 2, 4, 7 y 8.
Todas estas configuraciones pasan. Se comprueban la precarga, los N ciclos
completos, la retención del contador en LISTO, los cuatro valores de D0 sin
latencia adicional, reset/retirada/fallo en los cuatro estados operativos,
enclavamiento de FALLO, recuperación con reset y los tres códigos de estado
inválidos. También se comprueba la prioridad reset > fallo > petición.

El testbench modela OEN y Z con asignaciones triestado; **no instancia ni
valida primitivas Gowin**. La nueva prueba
`pixi run python -m unittest gateware.tests.test_lp_target -v` sí conecta los
tres RTL y el adaptador real generado por Migen, con modelos funcionales de
sus primitivas: reconstruye 18 paquetes / 204 bytes y comprueba pausas,
LP-11 final y abortos de reset/fallo durante transmisión.
Quedan pendientes simulación con biblioteca del fabricante, comprobación
independiente ECC/CRC en ese nuevo banco e inyecciones en cada fase.
Las regresiones existentes de `motor_lpdt`
y `secuenciador_init` también pasan, pero no incluyen este PHY.

## Cobertura de control y preparación

- Reset activo: `lp_preparada=0`, LP deshabilitado y HS deshabilitado.
- Sin petición no se habilita ningún driver.
- PRECARGAR mantiene datos `11` antes de habilitar LP.
- ESTABILIZAR dura N ciclos completos con todos los pares en LP-11.
- Comprobar N=1 y N=4, sin restas negativas ni contadores de ancho cero.
- No afirmar `lp_preparada` antes del final del intervalo.
- Petición mantenida no repite la preparación.
- Reset y retirada de petición en cada estado, incluido durante Mark/Space.
- `fallo_init` en cada estado: inhibición, FALLO enclavado y recuperación
  solo con reset; retirar el fallo o la petición no reinicia por sí solo.
- Estado inválido: no conducir y enclavar FALLO.

## Datos y buffers (primitivas reales pendientes)

- En LISTO probar D0=`00`, `01`, `10`, `11`, sin invertir P/N.
- D1 y CLK siempre `11` cuando LP esté habilitado.
- Comparar D0 del motor y D0 de pads simulados sin un ciclo adicional.
- TBUF LP: `OEN=0` conduce y `OEN=1` produce Z en el modelo.
- HS: los seis pines permanecen Z en todos los estados.
- Revisar con el netlist que no queden buffers HS habilitados por omisión.
- El modelo de pad debe distinguir datos internos de estado Z del conductor;
  no sustituir la comprobación por mirar únicamente `lp_oe`.

## Integración

Conectar ROM, secuenciador de 18 paquetes y motor LPDT de ancho 5 reales:

1. El motor no acepta antes de preparación y reposo inicial completos.
2. Reconstruir los 18 paquetes desde los pads LP simulados.
3. Comparar 204 bytes DSI, selector `87`, 18 ECC y 16 CRC aplicables.
4. Medir las pausas de 9/65 ms más el overhead ya documentado.
5. `terminado` aparece después del retorno físico simulado a LP-11.
6. Después de `init_completa`, todos los pares permanecen LP-11; HS en Z.
7. Reset/fallo durante el paquete de 22 bytes aborta sin envíos espontáneos.

Las simulaciones digitales no validan amplitud, impedancia, overshoot,
alimentaciones ni conformidad D-PHY. La prueba física requiere revisión
y autorización separadas. No se incorpora LiteX.
