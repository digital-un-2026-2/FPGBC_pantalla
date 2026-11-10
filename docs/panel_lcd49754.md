# Investigación de LCD-4975 / LCD-49754

Búsqueda realizada el 2026-11-10 para preparar la pantalla de la FPGBC.
El usuario amplió la referencia inicial LCD-4975 con este marcado físico:

```text
LCD-49754-001/111 3
MP3 L4N3352v0057724
```

El sufijo coincide exactamente con la especificación del LT031MDZ4000,
sección E, página 5. Se registra en `profiles/panel_identity.json`. No se ha
leído el ID del controlador. La búsqueda del segundo código no encontró una
decodificación pública; se conserva literalmente, sin atribuirle un IC.

## Evidencia pública

| Dato | Evidencia | Qué permite concluir |
|---|---|---|
| LCD-49754-001 ↔ JDI LT031MDZ4000 | [EarthLCD](https://earthlcd.com/products/earthlcd-3-1-720720) | Correspondencia de modelo, ahora respaldada por el marcado completo del usuario |
| Familia LCD-49754, 720×720, 24 bits/píxel y variantes -001/111 y -002/111 | [Especificación BlackBerry/JDI, versión externa 1B, pp. 1 y 5](https://www.panoxdisplay.com/uploadfile/datasheet/LT031MDZ4000.pdf) | Geometría/formato y existencia de más de un proveedor |
| LCD-49754-000 con driver R63308 y MIPI DSI | [Chance Display, especificación de su módulo](https://chance-display.com/product/3-0-inch-720720-mipi-interface-r63308-driver-ic-tft-lcd-module/) | R63308 es un candidato documentado para una variante comercial |
| Dos pares de datos D0/D1 y reloj, conector de 30 contactos | [Pinout de Chance Display](https://chance-display.com/product/3-0-inch-720720-mipi-interface-r63308-driver-ic-tft-lcd-module/) | Coincide en estructura con el enlace trazado en la FPGBC |
| LT031MDZ4000 utilizado a 60 Hz con placa conversora | [Artículo de sus autores, MoPeDT, sección 3.2.2](https://mlbrcht.com/publication/ieee-vr-mopedt/ieee-vr-mopedt.pdf) | Un caso de uso, no especificación de porches ni fps obligatorios del panel |
| Panel incluido en el kit FPGBC | [FunnyPlaying](https://funnyplaying.com/products/fpgbc-kit) | El fabricante del kit no publica allí una referencia de controlador o secuencia de registros |
| Driver JDI con inicialización DCS y modo de vídeo | [JamWu: panel-jdi-lt031mdz4000.c](https://github.com/jamwu/RPI-LCD-LT031MDZ4000/blob/main/panel-jdi-lt031mdz4000.c) | Secuencia pública utilizable como candidato: dos lanes RGB888, vídeo HSE, reloj no continuo |
| Ajuste de modo a 60 Hz | [Fork will-tm](https://github.com/will-tm/RPI-LCD-LT031MDZ4000/blob/main/panel-jdi-lt031mdz4000.c) | Total vertical de 750 líneas; front porch 22, VSYNC 5, back porch 3 |

LCD-4975 era la referencia abreviada disponible inicialmente. El marcado
completo permite trabajar con la variante -001/111 documentada. No se debe equiparar
automáticamente la variante vendida por Chance con todos los paneles JDI o
con todas las revisiones del kit.

## Perfil utilizado para la imagen de prueba

La búsqueda ampliada sí encontró inicialización y temporizaciones en el driver
JDI público. Esto corrige la conclusión previa de que no había una secuencia
disponible: sigue sin estar verificada para la unidad del usuario, pero permite
construir una prueba concreta. No se deduce de ello que todos los LCD-49754
utilicen el mismo controlador.

`profiles/lt031mdz4000_init.json` recoge los valores de registro y esperas de
ese driver (JamWu, GPL-2.0-only); el generador produce paquetes DCS en RTL.
El target [display_image](imagen_en_pantalla.md) arranca automáticamente con
esta inicialización y un cuadro de 750 líneas a 60 Hz. El driver también usa
un GPIO de RESET físico, conexión no disponible en este diseño: aquí se
envía software reset DCS. El modo HS por ráfagas de nuestra fuente no reproduce
exactamente las temporizaciones del host Raspberry Pi original.

Para 720×720 RGB888 a 60 Hz, solo los píxeles exigen
`720×720×24×60/2 = 373,248 Mbit/s` por lane, sin cabeceras ni blanking.
El perfil S320 de la cadena general no alcanza ese caso y su preparador largo
consume tres ciclos por byte. El target de imagen añade 480 Mbit/s/lane y una
ROM de línea que entrega dos bytes por ciclo. La plantilla genérica
`profiles/display_hs.template.json` permanece deshabilitada y no es el perfil
que usa el nuevo bitstream de imagen.

## Validación pendiente

Falta comprobar la recepción de la imagen y la fase real CLK/datos en la placa.
El usuario sigue sin retroiluminación con los dos bitstreams probados.
El pinout original, sección H, página 7, identifica el contacto 8 del LCD
como **salida PWM CBABC del panel**. No es el pin 8 de la FPGA ni una entrada
para un PWM del host. Falta seguir esa señal hasta el circuito de LEDs de la
FPGBC; no está demostrado que esa red sea la causa de la luz apagada.

La etiqueta resuelve la referencia, pero no valida la secuencia de registros.
Una captura de la placa original permitiría contrastarla. Las lecturas DCS de identidad
requerirían añadir recepción/BTA, que la cadena actual no implementa.
