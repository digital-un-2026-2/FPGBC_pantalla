# Interfaz física LP

[Inicio](../README.md) · [Hardware](../docs/hardware.md)

Diseño de la interfaz entre `secuenciador_init`, `motor_lpdt` y los seis
conductores del panel. **RTL y pruebas funcionales disponibles; sin validación eléctrica.**
Se conserva el nombre de carpeta solicitado, `fisical_layer`.

## Organización

| Carpeta | Contenido |
|---|---|
| [docs/](docs/README.md) | Flujo y datapath editables, y condiciones de integración |
| [src/](src/README.md) | Top LP combinacional y top autónomo con secuenciador y motor |
| [TB/](TB/README.md) | Prueba física, prueba integrada y modelos ideales de buffers |
| `Makefile` | Pruebas sin placa y ondas opcionales |

El bloque físico es combinacional: no necesita FSM propia ni temporizadores.
Las decisiones del flujo se evalúan continuamente, no son estados ni operaciones
que consumen ciclos. El top integrado conserva la FSM del secuenciador y la
del motor sin modificarlas. No se añaden BTA, receptor ni depuración LiteX.

## Simulación y conexión de los módulos

```sh
pixi run make -C fisical_layer test-all
```

`src/panel_init_top.v` conecta los tres bloques en Verilog:

```text
secuenciador_init ── solicitud, bytes y longitud ──→ motor_lpdt (ancho 4)
       ↑                                                │ estado_D0
       └────────── lp_preparada ─── fisical_layer ←──────┘
                                       │
                               puertos LP y ramas HS liberadas
```

`rst_motor` llega al motor y a la interfaz; `preparar_lp` habilita LP. El
handshake y `pos` siguen directamente entre motor y secuenciador. No se
registran de nuevo los datos de D0 ni los bytes de ROM. `clk` y `rst` son
entradas de integración: no se implementan PLL ni generador de reset de arranque.
Las esperas normales conservan los defaults existentes; la prueba integrada
solo acorta algunos parámetros de arranque, no las esperas DCS.

La prueba completa reconstruye los 11 paquetes desde los pads simulados y
comprueba ECC/CRC y 285 ms DCS. Ver [cobertura y límites](TB/README.md).

## Entradas y salidas de `fisical_layer`

Los nombres existentes se reutilizan sin cambiar el contrato del secuenciador
ni el del motor. Las señales nuevas solo pertenecen a la interfaz física.

| Señal | Dirección | Origen / destino | Condición |
|---|---|---|---|
| `preparar_lp` | Entrada | Salida existente del secuenciador | Solicita habilitar la interfaz LP |
| `rst_motor` | Entrada | Salida existente del secuenciador | Deshabilita LP durante reset global o aborto por fallo; sigue conectado también al reset del motor |
| `estado_D0[1:0]` | Entrada | Salida existente del motor | Bit 1=P, bit 0=N; camino sin registros adicionales |
| `liberar_d0` | Entrada nueva | Sin controlador BTA | Libera ambos conductores; el top autónomo la fija a cero |
| `lp_preparada` | Salida | Entrada existente del secuenciador | Condición interna de conducción LP, no respuesta del panel |
| `d0_pad_p`, `d0_pad_n` | Salidas nuevas | Salidas O de los dos IOBUF | Niveles digitales de los pads, sin sincronización ni decodificación |
| `hs_oen[5:0]` | Salida lógica nueva | Conectada a seis TBUF del bloque | Constante `111111`: todos los buffers HS deshabilitados |
| `hs_pads[5:0]` | Salidas liberadas | Salidas de esos seis TBUF | Orden conceptual 0…5: CLK_N, CLK_P, D1_N, D1_P, D0_N, D0_P |
| D0 P/N | Bidireccionales | Pines 122/123 mediante 100 Ω por conductor | Dos IOBUF |
| CLK P/N, D1 P/N | Salidas liberables | Pines 126/128 y 124/125 | LP-11 al habilitar; liberadas al deshabilitar |
| Ramas HS | Salidas deshabilitadas | Pines 112–117 | Deshabilitación explícita de sus drivers en todos los casos |

`d0_oen` es un nombre interno, conectado al OEN de ambos IOBUF:
0 conduce, 1 libera. No es una salida del motor ni del secuenciador.
`lp_aux_oen` denomina el control interno equivalente para CLK y D1.

## Lectura del flujo

1. `rst_motor=1` o ausencia de `preparar_lp`: liberar todas las ramas LP y
   mantener HS sin conducir. `lp_preparada=0`.
2. Interfaz habilitada: CLK y D1 conducen LP-11.
3. Si `liberar_d0=1`: liberar ambos IOBUF D0 y exponer sus lecturas;
   `lp_preparada=0`. No se ejecuta BTA.
4. En otro caso, conducir directamente `estado_D0`; `lp_preparada=1` tanto
   en reposo como durante transmisión. El motor ya genera LP-11 en reposo:
   **debe haber completado su reset antes de habilitar las salidas**.

No se usa `permiso_arranque` como habilitación física: el secuenciador solo lo
activa en SOLICITAR y retirarlo no aborta al motor. Tampoco se usan pulsos
`aceptado` o `terminado` para memorizar modos. El motor conserva el handshake
directo con el secuenciador y este conserva todas sus esperas.

## Datapath

La segunda página de `docs/FISICAL_LAYER.drawio` muestra únicamente puertas,
buffers sintetizables y señales lógicas, siguiendo el estilo sin colores de
los otros datapaths. Los números de pin, resistencias, bancos y constraints
quedan fuera de esa página. No se cambian las interfaces del motor ni del
secuenciador existentes.

Relaciones combinacionales implementadas:

```text
habilitar_lp = preparar_lp AND NOT rst_motor
lp_aux_oen   = NOT habilitar_lp
d0_oen       = lp_aux_oen OR liberar_d0
lp_preparada = NOT d0_oen

IOBUF_P.I    = estado_D0[1] IOBUF_N.I = estado_D0[0]
IOBUF_P.OEN  = d0_oen       IOBUF_N.OEN = d0_oen
d0_pad_p     = IOBUF_P.O    d0_pad_n = IOBUF_N.O
hs_oen[5:0]  = 111111
```

`habilitar_lp`, `d0_oen` y `lp_aux_oen` son nombres internos. La
lógica se reduce a tres inversores, una AND y una OR; la síntesis podrá
optimizarla. El camino D0 no tiene mux ni registros añadidos. No entran `ocupado`,
`fallo` ni un reset adicional al bloque físico. No se necesitan archivos RTL
independientes para cada puerta.

Los bloques de E/S son dos IOBUF para D0, cuatro TBUF para CLK/D1 con dato
constante 1 y `lp_aux_oen` común, y seis TBUF HS siempre deshabilitados.
La legalidad de las primitivas y su configuración por rama requieren revisión
para una implementación física.
Las etiquetas D0_P/N y CLK/D1 son puertos lógicos, no asignaciones de pin.
`hs_oen` está conectado a los seis TBUF HS en el RTL. **La simulación no prueba
la deshabilitación efectiva en la placa**: faltan constraints, revisión de
implementación, pulls, terminaciones y comportamiento durante configuración.

`lp_preparada` refleja la condición lógica interna de conducción, no
una lectura de pads ni una medida del tiempo de habilitación de los buffers.
No depende de `ocupado`, de los datos del motor ni de `permiso_arranque`, por
lo que no crea un lazo combinacional con la aceptación de una solicitud.

## Coordinación y límites pendientes

- Mantener `rst_motor` durante un posedge y el negedge siguiente. Antes de
  habilitar LP, el motor debe estar inicializado y su D0 en LP-11. Se elimina
  el mux protector: no se admite habilitar con la salida del motor desconocida.
- Validar glitches de habilitación, retardos y timing real del camino
  motor → IOBUF antes de implementar. No se añaden esperas a la interfaz;
  estabilización y reposo inicial permanecen en el secuenciador.
- `liberar_d0` se fija a cero en `panel_init_top`; no tiene controlador BTA.
  Una futura escucha exige impedir
  nuevas solicitudes y coordinar el fin o aborto del envío antes de liberar.
  Liberar durante un envío lo trunca. Al bajar esta entrada se vuelve a conducir:
  **el controlador externo debe impedirlo hasta autorizar la recuperación del
  enlace**; no inferir propiedad del enlace por observar LP-11.
- El secuenciador actual considera pérdida de `lp_preparada` un fallo desde
  REPOSO_INICIAL hasta LISTO. Por tanto, la escucha no es un modo integrado del
  arranque actual. El fallo queda enclavado, sin reintentos automáticos.
- En FALLO, el secuenciador mantiene `preparar_lp=1` y activa `rst_motor`.
  La conexión de `rst_motor` a esta interfaz libera las salidas sin
  necesitar `fallo` por separado; no se modifica la FSM existente.
- No duplicar estabilización, reposo inicial, esperas DCS ni timeouts del
  secuenciador. La interfaz no observa alimentación estable ni recepción DSI.
- GW2AR-LV18EQ144PC8/I7: BANK0 medido a 1,21 V; LVCMOS12 es candidato
  documentado, no conformidad D-PHY. Pendientes niveles, corrientes, flancos,
  cargas, pulls, keeper, terminaciones y comportamiento durante configuración.
- Las ramas HS 112–117 necesitan buffers explícitamente deshabilitados y
  revisión de su configuración efectiva. No basta dejarlas sin utilizar.
  Liberar una salida no garantiza por sí solo ausencia de pulls o terminaciones.
- Las lecturas de pads son señales potencialmente asíncronas. Su tratamiento
  pertenece a un futuro receptor, no a este flujo. No se diseñan BTA, receptor
  LP, paquetes, vídeo HS ni retroiluminación.
