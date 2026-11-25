# Reglas de diseño RTL

Estas reglas se aplican a todos los módulos nuevos del proyecto.

## 1. Organización y responsabilidades

Usar la estructura de [`motor_phy/`](../motor_phy/README.md):

```text
<modulo>/
├── Makefile  Pruebas y simulación
├── docs/     Diseño editable en Draw.io
├── src/      RTL del módulo y sus componentes
├── TB/       Bancos de pruebas
└── waves/    Vistas de GTKWave opcionales
```

El top del módulo conecta sus componentes. Separar las piezas del datapath
en archivos propios cuando tengan responsabilidades distintas, como los
[contadores, comparadores, registros y multiplexores de `motor_lpdt`](../motor_lpdt/src/README.md).
Reutilizar bloques existentes si encajan sin cambiar su contrato. No
crear un archivo nuevo por cada asignación trivial.

## 2. Flancos y lógica combinacional

- **Datapath:** sus registros y contadores actualizan en `negedge`.
- **FSM:** su estado actualiza en `posedge`.
- Los multiplexores, comparadores y decodificadores son combinacionales.
- Mostrar en el diseño el ancho, el reloj, las habilitaciones y el reset de
  cada registro. Indicar el nivel activo, el flanco si es síncrono y el valor
  de reset. Distinguir el reset del módulo del reinicio de una transacción.
- En el diseño, indicar qué captura o actualiza cada flanco, cuándo
  están estables los datos y cómo se evita perder información en los
  caminos de medio ciclo. Si el reset es síncrono y afecta a ambos
  flancos, debe cubrir ambos.
- Si el datapath intercambia datos con otros módulos, acompañar la revisión
  con una tabla de flancos que cubra el arranque, el primer y último dato
  y la indicación de fin, según aplique. Distinguir cuándo se presenta una
  palabra de cuándo se consume; si el flanco no está fijado, marcarlo como
  propuesta (ver §7).

## 3. Patrón para FSM

Seguir [`phy_control.v`](../motor_phy/src/phy_control.v): las decisiones
de transición se escriben dentro del bloque secuencial
`always @(posedge clk)`, sin un bloque combinacional `next_state`
separado. Las salidas de control se decodifican en `always @(*)`,
con asignaciones por defecto para evitar latches.

Un contador con decodificación de rangos no exige una FSM de fases.
No agregar estados de control que no correspondan al módulo.

## 4. Organización visual de los diagramas

Guardar la fuente editable como `docs/<MODULO>.drawio` dentro del módulo,
con una página por vista aplicable. Usar como referencia visual el
directorio `MIPI_LCD/Docs/` de **`digital_UN`**, no los diagramas locales
de `motor_phy` o `motor_lpdt`:

| Vista | Referencia en `MIPI_LCD/Docs/` | Convención |
|---|---|---|
| Datapath | `MIPI_LCD_arquitectura.pdf` para el estilo de conexiones; `MIPI_TX_componentes.pdf` para la agrupación funcional. | Etiquetas junto a los puertos en ambos extremos; consultar la convención de abajo. |
| FSM | `LINK_FSM` en `MIPI_TX_componentes.pdf` y `MIPI_TX_secuencia.svg` | Mostrar estados, condiciones de avance, retornos y señales de control conforme al contrato. La organización visual no sustituye el patrón RTL de la regla 3. |
| Flujo | `CTRL_flujo_inicio.svg` | Cajas con asignaciones de señales, rombos con la condición y ramas `Sí`/`No`. Secuencia principal vertical y bucles de espera o retorno a los lados. Es referencia visual, no fuente de las interfaces vigentes. |

Mantener los mismos nombres y anchos de señales entre vistas. Si se
generan exportaciones, partir del `.drawio` en lugar de editarlas a mano.

### Convención visual para datapath

- **Bloques.** Agrupar los componentes internos dentro del contorno del módulo
  y dejar fuera los módulos vecinos. Usar cajas claras y títulos en negrita.
  Reservar espacio junto a los bordes para los puertos. Poner las ecuaciones,
  la secuencia de palabras o las notas de flancos en un recuadro de la misma
  página si no caben sin tapar señales.
- **Puertos.** Rotular cada conexión en ambos extremos, junto al puerto
  emisor y al receptor, dentro de sus cajas y alineada con el terminal.
  Distinguir visualmente la etiqueta del título del bloque y escribir el
  rango completo de cada bus, por ejemplo `WORD[15:0]`. Si un extremo no
  tiene bloque dibujado, rotular el terminal externo.
- **Señales.** Usar trayectos ortogonales, un color por señal tanto para
  el cable como para sus etiquetas, trazo fino para un bit y grueso para
  buses. Las flechas apuntan al receptor. Solo las ramas de una misma
  señal repiten color, incluso si el puerto receptor tiene otro nombre.
- **Cruces.** Separar las rutas para que se puedan seguir sin cruzar
  etiquetas. Marcar con un punto lleno las ramificaciones reales y con
  un corte en uno de los trazos los cruces sin unión.
- **Revisión.** Abrir o renderizar el `.drawio` y comprobar que a escala de
  página se distinguen los nombres, anchos, flechas y ramificaciones.

Ejemplo: [`HS_PACKER.drawio`](../mipi_tx/hs_packer/docs/HS_PACKER.drawio).
De `MIPI_LCD_arquitectura.pdf` se toma el estilo visual, **no** las
interfaces del TOP anterior de 8 bits; manda el contrato de la §7.

## 5. Orden de diseño

Dibujar primero el **flujo** si aplica, después el **datapath** y al
final la **FSM** si existe. Si el módulo solo tiene datapath, dibujar
únicamente esa vista. No crear páginas, estados ni bloques por cumplir
una plantilla.

## 6. Aprobación antes del RTL

Presentar los diagramas, las interfaces y los puntos de temporización
necesarios para revisarlos. **Detenerse y esperar aprobación explícita.**
El RTL y los bancos de pruebas se escriben después de aprobar el diseño,
no en paralelo con los diagramas.

## 7. Contrato de arquitectura

La arquitectura vigente de
`../digital_UN/basic_circuits/test_peripherals/rtl/cores/MIPI_LCD/`
(ruta desde la raíz del repositorio) es el contrato fijo. Para `MIPI_TX`
mandan `Docs/MIPI_TX_componentes.pdf`, `Docs/MIPI_TX_bloques.pdf` y
`Docs/MIPI_TX_adopcion.md`, no las interfaces de los diagramas
anteriores. No modificar el repositorio vecino para acomodar el diseño.

Si el contrato no fija una interfaz, un significado o un flanco,
señalar el punto abierto y presentar una propuesta para aprobación.
No agregar puertos, estados o responsabilidades ni tratar una hipótesis
de captura como requisito del contrato.

## 8. Simulación y formas de onda

Para módulos nuevos con banco de pruebas, ofrecer estos objetivos en su
`Makefile`:

| Objetivo | Comportamiento |
|---|---|
| `test` | Compilar y verificar sin abrir GTKWave ni generar ondas por defecto. |
| `sim` | Compilar y ejecutar el mismo banco con volcado de ondas; si termina correctamente, abrir GTKWave. |
| `wave` | Abrir el último volcado sin recompilar. Si no existe, indicar cómo generarlo con `sim`. |

Activar `$dumpfile` y `$dumpvars` con `+waves` solo en el banco, sin
cambiar los estímulos ni las comprobaciones. Preferir FST y volcar las
señales necesarias para revisar el protocolo y sus flancos, no memorias
completas. Guardar los ejecutables y las ondas en `build/<modulo>/` (desde
la raíz) sin versionarlos.

Si se guarda una vista de señales, usar `waves/<banco>.gtkw`, sin rutas
absolutas, y cargarla desde el objetivo `wave`. Ejemplo desde la raíz:

```sh
pixi run --locked make -C mipi_tx/hs_packer sim
```
