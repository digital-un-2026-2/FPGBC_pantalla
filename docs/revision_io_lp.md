# Revisión previa a placa: E/S LP

Estado: **solo revisión offline; no autoriza cargar la FPGA**.
No hay medición disponible en esta etapa. No se cambian resistencias ni
alimentaciones. Se fijan explícitamente DRIVE=8 y FAST, conservando el
perfil LP que antes dependía de defaults. Se audita el empaquetador y se
genera un candidato marcado `UNMEASURED`, sin cargar hardware.

## Qué se ha contrastado

| Comprobación | Resultado y límite |
|---|---|
| Dispositivo | La base Apicula reconoce `GW2AR-LV18EQ144PC8/I7`: `GW2AR-18C`, `eLQFP144P`, `C8/I7` |
| Mapa enrutado | Coinciden los doce pines DSI y el reloj con la base del encapsulado |
| Bancos | LP en BANK0; HS en BANK1; reloj pin 11 en BANK7 |
| Ramas HS | Se usan seis IOBUF GPIO, no transmisores diferenciales; OEN=1 y NET_OEN=VCC en los seis |
| Fusibles HS | La selección del packer conserva ODMUX_1=0, LVDS_OUT=OFF y BANK_VCCIO=2.5 |
| Pulls DSI | Los doce pads conservan NONE tanto en el JSON como en los atributos comprobados del packer |
| Serialización | Al releer el candidato se obtiene exactamente el mapa de fusibles comprobado |
| Tiempos internos | Place-and-route a 40 MHz pasa; no contiene un contrato temporal externo del receptor |
| Niveles sobre el panel | **No medidos** |

El orden D0/D1/CLK se verifica siguiendo las conexiones hasta los puertos,
no por los sufijos de los nombres automáticos que genera Yosys.
La base de las herramientas corrobora el encapsulado, no sustituye
la revisión de la placa física ni las especificaciones del fabricante.

## Corriente LP: no dejar implícita para una prueba

[DS226-2.7E](https://cdn.gowinsemi.com.cn/DS226E.pdf), tabla 2-1,
página impresa 11, enumera **4/8 mA** para salidas LVCMOS12 con VCCIO de 1,2 V.
La tabla 3-10 da el intervalo de alimentación 1,14–1,26 V.
Esto es compatible con el banco medido a 1,21 V, no una validación del panel.

El código de la versión local de Apicula, `gowin_pack.py`, inicializa
`TBUF` con **DRIVE=8**. Se ha fijado ese mismo valor explícitamente en el
platform: no cambia el perfil anterior, pero evita depender de un default.
El packer comprobado exige que ese valor llegue a la codificación de fusibles.
Esto no es una medición ni una certificación del nivel sobre el panel.

La tabla 3-11 da condiciones DC de prueba, no una promesa de nivel D-PHY
con cualquier carga. En particular, la tabla de opciones y las condiciones DC
no deben confundirse ni extrapolarse a la red externa.
DRIVE expresa capacidad de conducción, no una fuente ideal que fuerza
exactamente esos mA sobre el panel.

**Pendiente:** contrastar el perfil con el modelo/carga del panel y comprobar
niveles y flancos. 4 mA es otra opción documentada para estudiar, no se ha
seleccionado ni aprobado automáticamente.

## Slew: soporte por resolver

El packer local inicializa `TBUF` con **SLEWRATE=FAST**. Se conserva de
forma explícita y se comprueba en la selección de fusibles.
Por tanto, 5 Mbit/s LPDT no implica flancos lentos.

Hay una limitación documental importante:

- DS226-2.7E, historial, revisión 2.2E del 27/02/2023: se retiró la
  información sobre slew rate.
- [UG289-2.2.1E](https://cdn.gowinsemi.com.cn/UG289E.pdf), historial,
  revisión 2.1.2E del 22/02/2023: se retiró su descripción.

No se cambia a `SLOW` por analogía. La aceptación de FAST por la herramienta
y su codificación en fusibles tampoco sustituyen documentación/modelo
específico o medición antes de declarar adecuado el perfil para el panel.

## Arranque, aislamiento y empaquetado

UG289-2.2.1E, sección 3.3, página impresa 6, y DS226-2.7E, sección 2.4,
indican GPIO sin conducción fuerte y con pull-ups débiles durante
configuración. Los pines relacionados con configuración dependen del modo.

Consecuencias:

- `PULL_MODE=NONE` del CST y `OEN=1` del RTL no controlan el período
  anterior a completar configuración.
- Los pines HS están conectados directamente al conductor del panel;
  no dar por seguro ese período solo porque el RTL los deshabilite.
- El target aislado deja de conducir después de configuración,
  **no garantiza tensión cero ni LP-11 sobre el panel**.
- También hay que revisar los pines de placa que no usa el nuevo top.
- El reset de 16 ciclos es local; no resetea ni detecta alimentación del LCD.

La versión anterior instanciaba TLVDS_TBUF, con fusión diferencial y metadata
de OEN incompleta. Se ha retirado ese transmisor innecesario para este objetivo:
ahora cada rama HS tiene un IOBUF GPIO con salida deshabilitada y lectura
ignorada. El banco medido a 2,52 V se declara LVCMOS25, pero no se conducen
esos 2,5 V sobre el panel.

Se usa IOBUF en lugar de TBUF en HS porque el packer instalado omite TBUF
en una de las listas de selección de tensión de banco. IOBUF conserva
correctamente BANK1=2.5 y permite verificar OFF estático. No se añade
funcionalidad de recepción.

Se encontró además un defecto en el seguimiento de pads usados: el packer
instalado deja vacío `_banks[bank].bels` y vuelve a procesar esos pads en
su bucle de pines no utilizados. `scripts/pack_lp_checked.py` corrige el
registro en memoria y exige que cada pad esperado se codifique una sola vez.
No se modifica el paquete instalado.

La auditoría captura los atributos reales entregados al codificador y
comprueba que sus fusibles estén presentes tras routing, placement y
tratamiento de constantes. Para HS exige `ODMUX_1=0`, `LVDS_OUT=OFF`,
`PULLMODE=NONE` y banco de 2,5 V. La decodificación genérica de Apicula
puede devolver nombres de estándares/drive ambiguos; no se usa esa
decodificación para afirmar una equivalencia eléctrica.

## Auditor reproducible

Con el JSON de revisión ya enrutado:

```sh
pixi run python -m gateware.tests.review_io \
  build/fpgbc_lp_gpio_review/fpgbc_lp_init_routed.json

pixi run python -m gateware.tests.review_fuses \
  build/fpgbc_lp_gpio_review/fpgbc_lp_init_routed.json

pixi run python -m unittest gateware.tests.test_review_io gateware.tests.test_review_fuses -v
```

El auditor solo lee archivos: contrasta pin/BEL/banco, estándar, pulls y
OEN, identifica ajustes implícitos y registra hashes de la base, el packer y
el JSON. No inicia síntesis, empaquetado ni comunicación con hardware.
Código de salida 0 significa que pasan las comprobaciones estructurales;
**no** significa permiso de carga. El informe mantiene `ready_for_board=false`.

Los tests de los auditores usan inyecciones sintéticas: pin incorrecto,
LP a 3,3 V, HS habilitado, banco incorrecto, pull-up, metadata ausente,
fusibles ausentes y DRIVE no enumerado. No sustituyen la
simulación de los tres RTL ni constituyen resultados eléctricos.

La variante activa pasó de nuevo simulación de 18 paquetes/204 bytes,
síntesis y place-and-route a 40 MHz (Fmax interna informada: 85,05 MHz).
El candidato revisado es
`build/fpgbc_lp_gpio_review/fpgbc_lp_init_UNMEASURED_checked.fs`, con informe
`.fs.review.json`. La relectura del archivo verifica igualdad completa de
su bitmap con el mapa comprobado. **No se ha cargado y no está medido**.
No usar imágenes anteriores ni `gowin_pack` directo.

### Documentos consultados

| Documento | Revisión | SHA-256 del PDF consultado |
|---|---|---|
| DS226 | 2.7E, 31/07/2026 | `198a50c84198a4a6aab7cf9dc57857f5c1b2b5c31392a0b4e89fccc84ac513ba` |
| UG289 | 2.2.1E, 19/12/2025 | `edec5c97e813e41cfbb6d49ab3bea2a8c8c28b92ec3234c74e865cbd4c88d1db` |

Los enlaces oficiales pueden cambiar de revisión. Se registran hechos y
referencias; no se incorporan copias de los manuales al repositorio.

## Orden de los siguientes pasos

1. Mantener el empaquetador comprobado: el control digital ya pasa.
2. Contrastar el perfil explícito con modelo y medidas del panel.
3. Confirmar revisión de placa y variante completa del panel.
4. Preparar observación de estados de diagnóstico y procedimiento de recuperación.
5. Con equipo de medida, revisar el arranque y los niveles/flancos LP en el
   panel. Solo entonces acordar una carga temporal y controlada, sin escribir flash.

No se añade reset DCS a la captura, vídeo ni tráfico HS.
