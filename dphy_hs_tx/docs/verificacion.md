# Plan de verificación antes de RTL

Plan previo al RTL, conservado como trazabilidad. El secuenciador y sus
pruebas ya están implementados: [resultados ejecutados](../README.md).
El wrapper de primitivas y pads sigue pendiente.

Sí se ha ejecutado la [comprobación de especificación](verificar_contrato.py):
PASS para perfil S320, seis longitudes (1/2/3/4/1083/2048 palabras) y cuatro
rechazos (Prepare corto/largo, underflow y lane parcial). No es una simulación
de PHY. El [contrato temporal](contrato_temporal.md) fija sus hipótesis.

El arnés de transporte/árbitro reales también pasa para 1/2/3/2048 palabras:
primera captura, last, parada y retirada normal de grant. Fuente y comandos
reproducibles están en el contrato temporal. Los ACK del arnés son funcionales;
no representan tiempos eléctricos ni prueban las salidas seriales.

El datapath propuesto añade una [comprobación de diseño](verificar_datapath.py):
PASS para ocho duraciones, POST concurrente con Exit, seis pipelines, Sync y
cuatro combinaciones de Trail. Ejecución: `python dphy_hs_tx/docs/verificar_datapath.py`.
No es una prueba de una implementación RTL de PHY.

La [FSM ejecutable de especificación](verificar_fsm.py) pasa siete recorridos
(seis longitudes y uno con demoras), reset y aborto en los 25 estados, 16
fallos dirigidos y siete códigos no usados. Comprueba también exclusión de
ACK/HS durante reset/aborto y relaciones de habilitación reloj/datos. Ejecutar
con `python dphy_hs_tx/docs/verificar_fsm.py`. No sustituye una futura prueba
del RTL ni genera formas de onda eléctricas.

| Escenario | Oráculo / aceptación |
|---|---|
| Perfil inválido o no representable | Rechazo antes de comenzar; comprobar mínimos, máximos, sumas y resolución temporal. |
| Preparación con ACK/grant demorado | Registrar transiciones públicas; ningún SoT separado de bytes por una espera ilegal; demostrar ocupación de almacenamiento. |
| Patrón serial | Reconstruir bytes a partir del reloj y bits de salida, con monitor separado del DUT; no leer FSM, índices ni shift registers internos. |
| Pares: 4, 6, 2166 y 4096 bytes | Comparar exactamente D0/D1 con bytes aceptados por packer; primer byte por D0; sin pérdida, duplicado ni burbujas. |
| Patrones 00/FF/55/AA/01/80 y secuencia incremental | Orden de bits, polaridad, relación reloj/datos y último bit por lane, según vectores independientes pendientes. |
| last y parada durante drenaje | Último bit antes de Trail; ACK de datos tardío; reloj mantenido hasta cumplir POST; complete solo después del reposo. |
| keep=01/00/10 | Modelo restringido propuesto: fallo sin transmitir la palabra inválida ni declarar éxito; para soporte impar real, nuevo oráculo normativo antes de habilitarlo. |
| Interrupción de valid o pérdida de grant | Fallo persistente, primera causa, sin reintento ni éxito. |
| Reset/aborto/pérdida PLL en cada fase | Descartar datos y confirmaciones obsoletas; recuperación por reset coordinado; distinguir lógica simulada de respuesta eléctrica pendiente. |
| Competencia LP/HS | Motor LPDT real + árbitro + transporte; reconstruir LP desde D0 y HS desde bits; exclusión de propiedad y retorno conjunto. |
| Nuevo paquete tras complete | Sin datos antiguos ni ACK perteneciente a otra transacción. |

Medir Prepare, Zero, Sync, Trail, Exit, CLK-PRE/POST en transiciones observadas
y comprobar relaciones de reloj con tolerancias declaradas por el perfil.
Usar watchdog de testbench; no inventar un timeout funcional para la PHY.

Las simulaciones futuras deben informar perfil exacto, fuente de vectores,
paquetes completos y abortos. Ejecutar después regresiones de preparadores,
packer, transporte, puente y árbitro con las tareas Pixi existentes.
Para wrapper: modelo oficial de primitivas, elaboración, síntesis, P&R y STA
independientes. La prueba funcional no acredita conformidad eléctrica.

Verificación de esta entrega documental: enlaces locales, XML Draw.io y
exportación SVG. No corresponde ejecutar regresiones RTL por estos cambios.
