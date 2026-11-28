# Referencia de la API gráfica `unal_``gfx` — borrador 0.1

Nov 26, 2026

Contrato entre software y hardware: el mismo `unal_``gfx.h` se implementa sobre raylib (PC) y sobre el hardware (FPGA). Los valores marcados como *propuesto* se fijan en el diseño; las firmas y los efectos son los que el equipo de software puede usar desde ya.

## 1. Convenciones

- **Encabezado único.** `#include "unal_gfx.h"`. Todas las funciones usan el prefijo `unal_``gfx_`. El juego no llama a raylib ni a registros del hardware directamente.
- **Coordenadas.** `int16_t`, una por argumento (`x`, `y`), en píxeles lógicos; origen (0,0) arriba a la izquierda, x hacia la derecha, y hacia abajo. La pantalla lógica mide 360×360; el escalado a 720×720 es invisible para el software. En la CPU de 32 bits cada argumento viaja en su propio registro, así que empaquetar x e y no ahorra nada en la llamada; el empaquetado se hace donde sí importa, en las entradas que lee el hardware (sección 3).
- **Recorte.** Lo que cae fuera del destino o del rectángulo de recorte se descarta en silencio; no es un error.
- **Colores.** `unal_``gfx_color` es RGB565. El color `UNAL_``GFX_COLOR_KEY` significa "transparente" en el framebuffer y en imágenes copiadas con `UNAL_``GFX_KEYED`.
- **Direcciones.** Todas las direcciones son de 32 bits, el controlador de memoria adapta cada acceso al bus de 16 bits de la PSRAM. El juego no maneja direcciones de la memoria de video ni de los framebuffers: usa handles. Solo maneja direcciones de la ROM de recursos (`unal_``gfx_rom_addr`), que genera la herramienta de assets.
- **Nombres de memorias.** Cada memoria se nombra por su propósito: ROM de recursos, memoria de video, framebuffers, memoria de paleta, de tileset, de mapas y de sprites.
- **Cargas por DMA.** Imágenes, tiles, paletas y mapas se cargan con transferencias DMA(Direct Memory Access) desde la ROM de recursos. Los datos pequeños que la CPU pasa por argumento (una celda, un color) se copian antes de retornar.
- **Resultados.** Casi todas las funciones devuelven `unal_``gfx_result`; `UNAL_``GFX_OK` = 0 y los errores son negativos. Una función que falla no cambia nada.
- **Asincronía.** Los comandos de dibujo y las transferencias DMA se encolan y se ejecutan en el orden en que se llamaron. La función retorna al encolar, no al terminar. Si la cola está llena, la llamada espera hasta que haya espacio.
- **Cambios por frame.** Sprites, scroll, paleta, tileset y mapas de fondo y HUD se aplican juntos en el siguiente `unal_``gfx_present`. Nunca se ve un frame con cambios a medias.
- **Orden de capas** (de atrás hacia adelante): color de fondo → capa de fondo (tiles) → framebuffer (comandos de dibujo, luego sprites) → HUD (tiles).
- **Un solo contexto de ejecución.** No hay hilos ni procesos: la API se usa solo desde el bucle principal del juego. Las rutinas de interrupción (botones, temporizadores) no deben llamar funciones `unal_``gfx_`; guardan el evento (una bandera o una cola) y el bucle principal lo procesa. La HAL puede usar internamente las interrupciones de vsync y de fin de DMA; el juego no las ve.
- **Backend de PC.** Implementa lo mismo sobre raylib. La ROM de recursos es el mismo archivo binario cargado en RAM, y cada `unal_``gfx_rom_addr` es un desplazamiento dentro de él. Avisa por log cuando el juego exceda un límite del hardware (sprites, memoria, tiles).

## 2. Tipos y constantes

```c
typedef uint16_t unal_gfx_color;          // RGB565
#define UNAL_GFX_RGB(r, g, b)  /* r, g, b de 0 a 255 -> unal_gfx_color */

typedef struct { int16_t x, y, w, h; } unal_gfx_rect;

typedef uint32_t unal_gfx_rom_addr;       // dirección en bytes dentro de la ROM de recursos
typedef uint32_t unal_gfx_image;          // handle opaco de imagen (sección 3); 0 = UNAL_GFX_NONE
typedef uint32_t unal_gfx_sprite;         // handle opaco de sprite (sección 3); 0 = UNAL_GFX_NONE
typedef uint16_t unal_gfx_tile_entry;     // entrada de mapa de tiles (ver formato)

typedef enum {
    UNAL_GFX_OK                 =  0,
    UNAL_GFX_ERR_INVALID_ARG    = -1,     // argumento fuera de rango o puntero nulo
    UNAL_GFX_ERR_INVALID_HANDLE = -2,     // handle inexistente, liberado o de una generación anterior
    UNAL_GFX_ERR_NO_MEMORY      = -3,     // no hay memoria de video libre suficiente
    UNAL_GFX_ERR_NO_SLOTS       = -4,     // no quedan slots de sprite o descriptores de imagen
    UNAL_GFX_ERR_STATE          = -5,     // llamada fuera de orden (p. ej. dibujar en pantalla sin frame abierto)
    UNAL_GFX_ERR_IN_USE         = -6,     // el recurso está referenciado (p. ej. imagen usada por un sprite)
    UNAL_GFX_ERR_NOT_INIT       = -7,     // falta unal_gfx_init
    UNAL_GFX_ERR_DEVICE         = -8      // el hardware no responde
} unal_gfx_result;

enum {                               // flags de copia; se combinan con OR
    UNAL_GFX_FLIP_H = 1 << 0,
    UNAL_GFX_FLIP_V = 1 << 1,
    UNAL_GFX_KEYED  = 1 << 2              // no copiar píxeles iguales a UNAL_GFX_COLOR_KEY
};

typedef enum {                       // dirección del degradado
    UNAL_GFX_GRAD_H = 0,                  // varía de izquierda a derecha
    UNAL_GFX_GRAD_V = 1                   // varía de arriba a abajo
} unal_gfx_grad_dir;

// Formato de unal_gfx_tile_entry: bits 0-9 índice de tile, bit 10 flip H, bit 11 flip V, bits 12-15 reservados (0)
#define UNAL_GFX_TILE(index, flags)  /* arma una unal_gfx_tile_entry; flags = UNAL_GFX_FLIP_H / UNAL_GFX_FLIP_V */

typedef struct {
    int16_t  screen_w, screen_h;
    uint16_t max_sprites, free_sprites;
    uint16_t max_images, free_images;
    uint16_t max_tiles;
    uint32_t vram_total, vram_free;  // bytes de memoria de video
    const char* backend;             // "pc-raylib" o "fpga"
} unal_gfx_info;
```

| Constante | Valor | Significado | Estado |
| --- | --- | --- | --- |
| `UNAL_``GFX_SCREEN` | 0xFFFFFFFF | Handle especial: framebuffer trasero del frame en curso, como destino de dibujo | Fijo |
| `UNAL_``GFX_NONE` | 0 | Handle inválido | Fijo |
| `UNAL_``GFX_SCREEN_W`, `UNAL_``GFX_SCREEN_H` | 360, 360 | Tamaño de la pantalla lógica | Fijo |
| `UNAL_``GFX_TILE_SIZE` | 8 | Lado de un tile en píxeles | Fijo |
| `UNAL_``GFX_PALETTE_SIZE` | 256 | Entradas de la paleta única; la entrada 0 es transparente | Decidido |
| `UNAL_``GFX_MAX_TILES` | 256 | Tiles en el tileset compartido (8 bpp, 64 B por tile, 16 KB) | Decidido |
| `UNAL_``GFX_BG_MAP_W`, `UNAL_``GFX_BG_MAP_H` | 64, 64 | Mapa de fondo en tiles (512×512 px, scroll circular) | Decidido |
| `UNAL_``GFX_HUD_MAP_W`, `UNAL_``GFX_HUD_MAP_H` | 45, 45 | Mapa del HUD en tiles (cubre la pantalla exacta) | Fijo |
| `UNAL_``GFX_MAX_SPRITES` | 128 | Slots de sprite | Decidido |
| `UNAL_``GFX_MAX_IMAGES` | 256 | Imágenes cargadas a la vez (descriptores) | Decidido |
| `UNAL_``GFX_MAX_IMAGE_DIM` | 360 | Ancho o alto máximo de una imagen, igual a la pantalla; una imagen ocupa como máximo 259.200 B | Decidido (por ahora) |
| `UNAL_``GFX_COLOR_KEY` | 0xF81F (magenta) | Color que significa transparente | Decidido |

## 3. Memorias, direcciones y handles

Cada memoria se nombra por su propósito. El juego solo ve la ROM de recursos (por dirección); las demás solo a través de funciones y handles. Ubicaciones y tamaños son propuestos.

| Memoria | Contenido | Ubicación | Tamaño | Acceso desde el juego |
| --- | --- | --- | --- | --- |
| ROM de recursos | Imágenes, tiles, paletas y mapas del juego, tal como los genera la herramienta de assets | ROM externa | Según el juego | Solo como origen de DMA (`unal_``gfx_rom_addr`) |
| Memoria de video | Imágenes cargadas: hojas de sprites, gráficos, superficies de composición | PSRAM | ≈ 3,5 MB (4 MB menos framebuffers) | Por handle `unal_``gfx_image` |
| Framebuffers A y B | Imagen que dibuja el blitter, 360×360 RGB565 | PSRAM | 2 × 259.200 B ≈ 500KB | Como `UNAL_``GFX_SCREEN` |
| Memoria de paleta | 256 colores RGB565 | BRAM/LUT | 512 B | `unal_``gfx_palette_*` |
| Memoria de tileset | 256 tiles de 8×8, 1 B por píxel | BRAM | 16 KB ≈ 8 blocks&#32; | `unal_``gfx_tileset_*` |
| Memoria de mapas | Mapa de fondo 64×64 y de HUD 45×45, 16 bits por celda | BRAM | 8.192 B + 4.050 B  ≈ 6 blocks&#32; | `unal_``gfx_bg_*`, `unal_``gfx_hud_*` |
| Memoria de sprites | Tabla de 128 entradas de 16 B | BRAM | 2 KB ≈ 1 block | `unal_``gfx_sprite_*` |

**Uso de BRAM.** La FPGA tiene 46 bloques de 18.432 bits = 847.872 bits en total. Con anchos de 8 o 16 bits cada bloque guarda 2 KB de datos (los 2.304 bits restantes son de paridad), así que hay ≈ 92 KB útiles. Las memorias de la API ocupan 16 bloques, el 35 %.

| Memoria | Bytes | Bloques |
| --- | --- | --- |
| Paleta | 512 | 1 (0 si va en LUT) |
| Tileset | 16.384 | 8 |
| Mapa de fondo | 8.192 | 4 |
| Mapa del HUD | 4.050 | 2 |
| Sprites | 2.048 | 1 |
| **Total** | **31.186** | **16 de 46** |

Quedan 30 bloques (≈ 60 KB) para el resto del diseño: colas de comandos y DMA, buffers de salida a la pantalla y lo que use la CPU del SoC.

**Direcciones.** 32 bits, el controlador de memoria adapta cada acceso al bus de 16 bits de la PSRAM. El direccionamiento es por palabra, además la memoria es compartida con el resto del sistema el cual la alinea a 4 bytes.

**Handles.** Un handle es un número opaco de 32 bits: bits 0–15 = índice en una tabla de descriptores que la HAL mantiene en la RAM de la CPU; bits 16–31 = generación, que aumenta cada vez que ese slot se libera. La dirección sola no alcanza: para liberar hay que saber el tamaño del bloque, para validar y recortar hay que saber ancho y alto, para no liberar una imagen en uso hay que contar referencias, y la generación detecta handles viejos que apuntan a un slot ya reutilizado.

Descriptor de imagen (en la HAL, ≈ 20 B):

| Campo | Bits | Uso |
| --- | --- | --- |
| Dirección base | 32 | Inicio de la imagen en memoria de video |
| Ancho, alto | 16 + 16 | Validar regiones y recortar |
| [Stride](https://medium.com/@oleg.shipitko/what-does-stride-mean-in-image-processing-bba158a72bcd) | 16 | Píxeles por fila en memoria (hoy igual al ancho) |
| Tamaño del bloque | 32 | Bytes que se devuelven al liberar |
| Referencias | 16 | Sprites que la usan; mayor que 0 impide liberarla |
| Generación | 16 | Debe coincidir con la del handle; si no, `UNAL_``GFX_ERR_INVALID_HANDLE` |
| Estado | 8 | Libre, en uso o liberación pendiente (DMA o comandos en curso) |

**Handle de sprite** (propuesto). Mismo formato de 32 bits: bits 0–15 = índice del slot, que es también el número de su entrada en la memoria de sprites (0 a 127); bits 16–31 = generación. La HAL guarda por cada slot un descriptor en la RAM de la CPU (≈ 24 B); la entrada de hardware es la copia que lee el blitter.

| Campo | Bits | Uso |
| --- | --- | --- |
| Imagen | 32 | Handle de la imagen origen; al cambiarla se resta una referencia a la anterior y se suma una a la nueva |
| Región origen | 4 × 16 | x, y, ancho y alto dentro de la imagen; con el descriptor de la imagen se calcula la dirección de la palabra 1 |
| Posición | 16 + 16 | x, y en pantalla (palabra 0) |
| Prioridad y flags | 8 + 8 | Prioridad, flip H, flip V, color clave y visible (palabra 3) |
| Generación | 16 | Debe coincidir con la del handle; si no, `UNAL_``GFX_ERR_INVALID_HANDLE` |
| Estado | 8 | Libre u ocupado |
| Palabras pendientes | 4 | Qué palabras de la entrada de hardware cambiaron; en `unal_``gfx_present` solo se escriben esas |

Un slot libre tiene el bit visible en 0 en su entrada de hardware, así el blitter lo salta sin consultar a la HAL.

**Entrada de sprite en hardware** (decidido, 4 palabras de 32 bits = 16 B). La HAL la calcula y la escribe; el hardware no conoce handles.

| Palabra | Bits | Contenido |
| --- | --- | --- |
| 0 | 15–0: x · 31–16: y | Posición en pantalla, con signo |
| 1 | 31–0 | Dirección en memoria de video del primer píxel de la región origen |
| 2 | 15–0: ancho · 31–16: alto | Tamaño de la región |
| 3 | 15–0: stride · 23–16: prioridad · 24: flip H · 25: flip V · 26: color clave · 27: visible · 31–28: reservado | Recorrido y atributos |

Guardar x e y en la misma palabra permite mover un sprite con una sola escritura de 32 bits, así el hardware nunca lee una posición a medias.

**Mapas, tileset y paleta.** Cada celda de mapa es una `unal_``gfx_tile_entry` de 16 bits; dos celdas consecutivas de una fila comparten una palabra de 32 bits (la de x par en los bits 15–0). El tile *i* empieza en la base de la memoria de tileset + 64 × *i*. Cada entrada de paleta ocupa 16 bits.

## 4. Ciclo de vida y frame

Un frame típico: `unal_``gfx_frame_begin` → comandos de dibujo y cambios de sprites/tiles → `unal_``gfx_present`.

| Función | Descripción | Argumentos | Retorna | Efectos |
| --- | --- | --- | --- | --- |
| `unal_``gfx_result unal_gfx_init(void)` | Inicializa la API y el hardware (en PC, abre la ventana de 720×720). Debe ser la primera llamada. | — | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_DEVICE`, `UNAL_``GFX_ERR_STATE` si ya estaba iniciada | Ambos framebuffers en `UNAL_``GFX_COLOR_KEY`; paleta en negro; tileset en ceros; mapas de fondo y HUD en tile 0 (transparente); sin sprites; scroll (0,0); fondo y HUD habilitados; color de fondo negro. |
| `void unal_gfx_shutdown(void)` | Libera todos los recursos y apaga la salida de video. | — | — | Todos los handles quedan inválidos. Después solo se puede llamar `unal_``gfx_init`. |
| `unal_``gfx_result unal_gfx_frame_begin(void)` | Abre un frame nuevo. Espera si el framebuffer trasero sigue en uso por el frame anterior. | — | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_STATE` si ya hay un frame abierto, `UNAL_``GFX_ERR_NOT_INIT` | `UNAL_``GFX_SCREEN` apunta al framebuffer trasero; destino = `UNAL_``GFX_SCREEN`; recorte = pantalla completa. **No borra el framebuffer**: su contenido es indefinido hasta que el juego llame `unal_``gfx_clear`. |
| `unal_``gfx_result unal_gfx_present(void)` | Cierra el frame y lo envía a pantalla en el siguiente retrazado vertical. No espera a que se muestre. | — | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_STATE` si no hay frame abierto | Encola el dibujo de los sprites visibles (encima de los comandos del frame); al vsync intercambia framebuffers y aplica juntos scroll, paleta, tileset y mapas. |
| `void unal_gfx_wait_vsync(void)` | Bloquea hasta el siguiente retrazado vertical. | — | — | Ninguno; sirve para sincronizar la lógica del juego. |
| `unal_``gfx_result unal_gfx_sync(void)` | Bloquea hasta que el blitter termine todos los comandos encolados. | — | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_NOT_INIT` | Ninguno sobre la imagen; útil para medir tiempos o para esperar a que terminen las transferencias DMA. |
| `uint32_t unal_gfx_frame_count(void)` | Número de frames presentados desde `unal_``gfx_init`. | — | Contador | Ninguno. |

## 5. Imágenes en memoria de video

Una imagen es un bloque RGB565 en la memoria de video: hojas de sprites, gráficos grandes o superficies donde componer. Ocupa ancho × alto × 2 bytes, como máximo 360×360. Se carga por DMA desde la ROM de recursos; la transferencia se encola junto con los comandos de dibujo, así que todo comando o sprite que use la imagen después de la carga la ve completa. El handle es válido en cuanto la función retorna; `unal_``gfx_sync` espera a que terminen todas las transferencias.

| Función | Descripción | Argumentos | Retorna | Efectos |
| --- | --- | --- | --- | --- |
| `unal_``gfx_result unal_gfx_image_create(int16_t w, int16_t h, unal_gfx_image* out)` | Reserva una imagen vacía, por ejemplo para componer en ella. | `w`, `h`: 1 a `UNAL_``GFX_MAX_IMAGE_DIM`; `out`: recibe el handle | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_ARG`, `UNAL_``GFX_ERR_NO_MEMORY`, `UNAL_``GFX_ERR_NO_SLOTS` | Consume w×h×2 B de memoria de video y un descriptor; todos los píxeles en `UNAL_``GFX_COLOR_KEY`. |
| `unal_``gfx_result unal_gfx_image_load(unal_gfx_rom_addr src, int16_t w, int16_t h, unal_gfx_image* out)` | Reserva una imagen y encola su carga por DMA desde la ROM de recursos. | `src`: dirección en la ROM del primer píxel; los w×h×2 B siguientes son la imagen por filas; `w`, `h` como arriba; `out`: recibe el handle | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_ARG` (src fuera de la ROM o tamaño fuera de rango), `UNAL_``GFX_ERR_NO_MEMORY`, `UNAL_``GFX_ERR_NO_SLOTS` | Igual que `create`; el contenido es el de la ROM desde que la transferencia se ejecuta en la cola. |
| `unal_``gfx_result unal_gfx_image_load_region(unal_gfx_image img, const unal_gfx_rect* region, unal_gfx_rom_addr src)` | Sobrescribe una región de una imagen existente desde la ROM, por ejemplo para traer otro cuadro de animación. | `img`: imagen (no `UNAL_``GFX_SCREEN`); `region`: dentro de la imagen; `src`: region.w×region.h×2 B por filas en la ROM | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_HANDLE`, `UNAL_``GFX_ERR_INVALID_ARG` | Encola la DMA; se ejecuta después de los comandos ya encolados que usan esa imagen. |
| `unal_``gfx_result unal_gfx_image_write(unal_gfx_image img, const unal_gfx_rect* region, const unal_gfx_color* pixels)` | Sobrescribe una región de una imagen con píxeles de la CPU: imágenes generadas en ejecución o cambios a imágenes cargadas desde la ROM. | `img`: imagen (no `UNAL_``GFX_SCREEN`); `region`: dentro de la imagen; `pixels`: region.w×region.h colores RGB565 en la RAM de la CPU, fila por fila | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_HANDLE`, `UNAL_``GFX_ERR_INVALID_ARG` | Copia los píxeles antes de retornar (el búfer puede reutilizarse) y la escritura se aplica en orden con la cola, después de los comandos ya encolados que usan esa imagen. El cambio es permanente. |
| `unal_``gfx_result unal_gfx_image_free(unal_gfx_image img)` | Libera una imagen. | `img`: imagen (no `UNAL_``GFX_SCREEN`) | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_HANDLE`, `UNAL_``GFX_ERR_IN_USE` si un sprite la referencia | La generación aumenta y el handle queda inválido de inmediato; la memoria de video y el descriptor se devuelven cuando terminan las transferencias y los comandos encolados que la usan. |
| `unal_``gfx_result unal_gfx_image_size(unal_gfx_image img, int16_t* w, int16_t* h)` | Consulta el tamaño de una imagen. | `img`: imagen o `UNAL_``GFX_SCREEN`; `w`, `h`: salida | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_HANDLE` | Ninguno. |

## 6. Dibujo inmediato (blitter)

Los comandos dibujan en el **destino actual** (`UNAL_``GFX_SCREEN` o una imagen) dentro del rectángulo de recorte. Dibujar en `UNAL_``GFX_SCREEN` solo es válido entre `unal_``gfx_frame_begin` y `unal_``gfx_present`; dibujar en una imagen es válido siempre (por ejemplo, para componer durante la carga). Dibujar con `UNAL_``GFX_COLOR_KEY` en la pantalla "borra" a transparente y deja ver la capa de fondo.

Salvo que se indique otra cosa, todos retornan `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_STATE` (pantalla sin frame abierto) o `UNAL_``GFX_ERR_INVALID_HANDLE` (destino liberado), y su efecto es encolar el comando.

**Los comandos modifican el destino de forma permanente**, sea una imagen o `UNAL_``GFX_SCREEN`; la imagen origen de un `unal_``gfx_blit` nunca cambia. Componer con `unal_``gfx_blit` sobre una imagen sobrescribe sus píxeles: para conservar el original hay que componer en una imagen nueva (`unal_``gfx_image_create`) o copiar antes el original con otro `unal_``gfx_blit`. Los sprites, en cambio, no modifican su imagen: el hardware solo la lee cada frame.

| Función | Descripción | Argumentos | Retorna | Efectos |
| --- | --- | --- | --- | --- |
| `unal_``gfx_result unal_gfx_set_target(unal_gfx_image target)` | Elige dónde dibujan los comandos siguientes. | `target`: `UNAL_``GFX_SCREEN` o una imagen | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_HANDLE` | Cambia el destino y restablece el recorte al destino completo. |
| `unal_``gfx_result unal_gfx_set_clip(const unal_gfx_rect* r)` | Limita el dibujo a un rectángulo del destino. | `r`: rectángulo en coordenadas del destino; `NULL` = destino completo | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_ARG` si w o h < 0 | Aplica a los comandos siguientes hasta otro `set_clip` o `set_target`. |
| `unal_``gfx_result unal_gfx_clear(unal_gfx_color c)` | Rellena el destino con un color. | `c`: color; `UNAL_``GFX_COLOR_KEY` deja la pantalla transparente | Común | Todos los píxeles del destino dentro del recorte toman `c`. |
| `unal_``gfx_result unal_gfx_draw_pixel(int16_t x, int16_t y, unal_gfx_color c)` | Dibuja un píxel. | `x`, `y`: posición; `c`: color | Común | Un píxel, si cae dentro del recorte. |
| `unal_``gfx_result unal_gfx_draw_line(int16_t x0, int16_t y0, int16_t x1, int16_t y1, unal_gfx_color c)` | Dibuja una línea de 1 px de grosor. | Extremos (ambos incluidos); `c`: color | Común | Los píxeles de la línea dentro del recorte. |
| `unal_``gfx_result unal_gfx_draw_rect(const unal_gfx_rect* r, unal_gfx_color c)` | Dibuja el contorno de un rectángulo, 1 px de grosor. | `r`: rectángulo (w, h ≥ 0); `c`: color | Común, o `UNAL_``GFX_ERR_INVALID_ARG` | Los 4 bordes dentro de `r`. w o h = 0 no dibuja nada. |
| `unal_``gfx_result unal_gfx_fill_rect(const unal_gfx_rect* r, unal_gfx_color c)` | Rellena un rectángulo. | Igual que `draw_rect` | Común, o `UNAL_``GFX_ERR_INVALID_ARG` | Todos los píxeles de `r` dentro del recorte. |
| `unal_``gfx_result unal_gfx_fill_gradient(const unal_gfx_rect* r, unal_gfx_color a, unal_gfx_color b, unal_gfx_grad_dir dir)` | Rellena un rectángulo con un degradado lineal de dos colores, opaco. | `r`: rectángulo (w, h ≥ 0); `a`: color inicial; `b`: color final; `dir`: `UNAL_``GFX_GRAD_H` (a a la izquierda, b a la derecha) o `UNAL_``GFX_GRAD_V` (a arriba, b abajo) | Común, o `UNAL_``GFX_ERR_INVALID_ARG` si w o h < 0, o si `a` o `b` es `UNAL_``GFX_COLOR_KEY` | Cada columna (H) o fila (V) de `r` toma un color intermedio entre `a` y `b`, canal por canal; la primera es exactamente `a` y la última exactamente `b` (con una sola columna o fila, `a`). Solo píxeles dentro del recorte. El redondeo exacto se define en el diseño y el modelo de referencia en C será su especificación. |
| `unal_``gfx_result unal_gfx_draw_circle(int16_t cx, int16_t cy, int16_t r, unal_gfx_color c)` | Dibuja el contorno de un círculo, 1 px de grosor. | Centro; `r` ≥ 0 (0 = un píxel); `c`: color | Común, o `UNAL_``GFX_ERR_INVALID_ARG` si r < 0 | Los píxeles del contorno dentro del recorte. |
| `unal_``gfx_result unal_gfx_fill_circle(int16_t cx, int16_t cy, int16_t r, unal_gfx_color c)` | Rellena un círculo. | Igual que `draw_circle` | Común, o `UNAL_``GFX_ERR_INVALID_ARG` | Todos los píxeles del disco dentro del recorte. |
| `unal_``gfx_result unal_gfx_blit(unal_gfx_image src, const unal_gfx_rect* src_rect, int16_t x, int16_t y, uint8_t flags)` | Copia una región de una imagen al destino. | `src`: imagen origen (no puede ser el destino actual); `src_rect`: región dentro de `src`, `NULL` = toda; `x`, `y`: esquina superior izquierda en el destino; `flags`: OR de `UNAL_``GFX_FLIP_H`, `UNAL_``GFX_FLIP_V`, `UNAL_``GFX_KEYED` | Común, o `UNAL_``GFX_ERR_INVALID_ARG` | Copia los píxeles volteados según `flags`; con `UNAL_``GFX_KEYED` omite los iguales a `UNAL_``GFX_COLOR_KEY`. Es la operación de composición: componer en una imagen y luego usarla como sprite. |

## 7. Sprites (tabla de objetos)

Un sprite es un slot persistente que apunta a una región de una imagen. El juego lo crea una vez y cada frame solo cambia lo necesario (posición, cuadro de animación). En `unal_``gfx_present`, el hardware dibuja los sprites visibles en el framebuffer **encima de todos los comandos de ese frame y debajo del HUD**, de menor a mayor prioridad; con igual prioridad, en orden de creación. Los cambios se ven a partir del siguiente `unal_``gfx_present`.

La HAL traduce cada sprite a una entrada de 16 B en la memoria de sprites: calcula la dirección del primer píxel a partir del descriptor de la imagen y de la región, y empaqueta posición, tamaño y atributos. Mientras un sprite use una imagen, la imagen cuenta esa referencia y no se puede liberar.

| Función | Descripción | Argumentos | Retorna | Efectos |
| --- | --- | --- | --- | --- |
| `unal_``gfx_result unal_gfx_sprite_create(unal_gfx_image sheet, unal_gfx_sprite* out)` | Reserva un slot de sprite. | `sheet`: imagen origen; `out`: recibe el handle | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_HANDLE`, `UNAL_``GFX_ERR_NO_SLOTS` | Estado inicial: oculto, posición (0,0), región = imagen completa, flags = `UNAL_``GFX_KEYED`, prioridad 0. |
| `unal_``gfx_result unal_gfx_sprite_destroy(unal_gfx_sprite s)` | Libera el slot. | `s`: sprite | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_HANDLE` | Deja de dibujarse desde el siguiente `present`; el handle queda inválido. |
| `unal_``gfx_result unal_gfx_sprite_set_image(unal_gfx_sprite s, unal_gfx_image sheet)` | Cambia la imagen origen. | `s`; `sheet`: imagen que contenga la región actual | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_HANDLE`, `UNAL_``GFX_ERR_INVALID_ARG` | Actualiza la imagen y conserva la región; resta una referencia a la imagen anterior y suma una a la nueva. Si la región actual no cabe en la nueva imagen, devuelve `UNAL_`GFX\_ERR\_INVALID\_ARG y no cambia nada. |
| `unal_``gfx_result unal_gfx_sprite_set_src(unal_gfx_sprite s, const unal_gfx_rect* src)` | Elige la región de la imagen que se muestra (cuadro de animación). | `s`; `src`: rectángulo dentro de la imagen, w y h > 0 | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_HANDLE`, `UNAL_``GFX_ERR_INVALID_ARG` | Cambia el tamaño y el contenido del sprite. |
| `unal_``gfx_result unal_gfx_sprite_set_pos(unal_gfx_sprite s, int16_t x, int16_t y)` | Mueve el sprite. | `s`; `x`, `y`: esquina superior izquierda en pantalla; puede quedar parcial o totalmente fuera | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_HANDLE` | Nueva posición; la parte fuera de pantalla se recorta. |
| `unal_``gfx_result unal_gfx_sprite_set_flags(unal_gfx_sprite s, uint8_t flags)` | Ajusta volteo y transparencia. | `s`; `flags`: OR de `UNAL_``GFX_FLIP_H`, `UNAL_``GFX_FLIP_V`, `UNAL_``GFX_KEYED` | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_HANDLE`, `UNAL_``GFX_ERR_INVALID_ARG` | Reemplaza los flags anteriores. |
| `unal_``gfx_result unal_gfx_sprite_set_priority(unal_gfx_sprite s, uint8_t p)` | Fija el orden entre sprites. | `s`; `p`: 0 a 255, mayor = más al frente | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_HANDLE` | Cambia el orden de dibujo. |
| `unal_``gfx_result unal_gfx_sprite_set_visible(unal_gfx_sprite s, bool visible)` | Muestra u oculta el sprite sin liberar el slot. | `s`; `visible` | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_HANDLE` | Un sprite oculto no consume tiempo del blitter. |

## 8. Paleta, tileset, fondo y HUD

Fondo y HUD comparten **un tileset** (tiles de 8×8, 1 byte por píxel = índice de paleta) en la memoria de tileset y **una paleta** de colores RGB565 en la memoria de paleta. El índice de paleta 0 es siempre transparente. El fondo tiene scroll; el HUD está fijo y cubre la pantalla exacta (45×45 tiles). Las cargas completas (paleta, tileset, mapas) son DMA desde la ROM de recursos; los cambios puntuales (una celda, un color) los escribe la CPU. Todos los cambios se ven a partir del siguiente `unal_``gfx_present`. Las regiones de mapa se expresan en tiles, no en píxeles. Un mapa es solo un arreglo de `unal_`gfx\_tile\_entry: cada celda referencia un tile del tileset; los píxeles están en el tileset.

**Paleta y tileset**

| Función | Descripción | Argumentos | Retorna | Efectos |
| --- | --- | --- | --- | --- |
| `unal_``gfx_result unal_gfx_palette_load(uint16_t first, uint16_t count, unal_gfx_rom_addr src)` | Carga entradas de la paleta desde la ROM. | `first` + `count` ≤ `UNAL_``GFX_PALETTE_SIZE`; `src`: `count` × 2 B en la ROM | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_ARG` | Encola la DMA a la memoria de paleta; cambia el color de todos los tiles que usan esos índices. El valor para la entrada 0 se ignora. |
| `unal_``gfx_result unal_gfx_palette_set(uint16_t index, unal_gfx_color c)` | Cambia un color desde la CPU, por ejemplo para fundidos o destellos. | `index`: 1 a `UNAL_``GFX_PALETTE_SIZE` − 1; `c`: color | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_ARG` | Una entrada de la memoria de paleta. |
| `unal_``gfx_result unal_gfx_tileset_load(uint16_t first, uint16_t count, unal_gfx_rom_addr src)` | Carga tiles en el tileset compartido desde la ROM. | `first` + `count` ≤ `UNAL_``GFX_MAX_TILES`; `src`: `count` × 64 B; cada tile son 8 filas de 8 índices | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_ARG` | Encola la DMA a la memoria de tileset; cambia todas las celdas de fondo y HUD que usan esos tiles. |
| `unal_``gfx_result unal_gfx_set_backdrop(unal_gfx_color c)` | Color que se ve donde fondo, framebuffer y HUD son transparentes. | `c`: color | `UNAL_``GFX_OK` | Cambia el color de fondo. |

**Fondo (con scroll)**

| Función | Descripción | Argumentos | Retorna | Efectos |
| --- | --- | --- | --- | --- |
| `unal_``gfx_result unal_gfx_bg_load_map(const unal_gfx_rect* region, unal_gfx_rom_addr src)` | Carga un bloque del mapa de fondo desde la ROM. | `region`: en tiles, dentro del mapa (sin envolver); `src`: arreglo en la ROM de region.w×region.h valores `unal_`gfx\_tile\_entry (16 bits cada uno), fila por fila; la celda (tx, ty) de la región está en src + 2 × (ty × region.w + tx). No contiene píxeles: cada valor solo dice qué tile del tileset va en esa celda y si se voltea | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_ARG` | Encola la DMA a la memoria de mapas. |
| `unal_``gfx_result unal_gfx_bg_set_tile(uint16_t tx, uint16_t ty, unal_gfx_tile_entry e)` | Cambia una celda del mapa de fondo desde la CPU. | `tx` < `UNAL_``GFX_BG_MAP_W`, `ty` < `UNAL_``GFX_BG_MAP_H`; `e`: entrada con `UNAL_``GFX_TILE` | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_ARG` | Una celda del mapa. |
| `unal_``gfx_result unal_gfx_bg_fill(const unal_gfx_rect* region, unal_gfx_tile_entry e)` | Llena un bloque del mapa de fondo con la misma entrada. | `region`: en tiles, dentro del mapa; `NULL` = mapa completo; `e`: entrada | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_ARG` | Ese bloque del mapa. |
| `unal_``gfx_result unal_gfx_bg_set_scroll(int16_t sx, int16_t sy)` | Fija qué píxel del mapa aparece en la esquina superior izquierda de la pantalla. | `sx`, `sy`: cualquier valor; se toman módulo el tamaño del mapa en píxeles | `UNAL_``GFX_OK` | Desplaza todo el fondo; el mapa se repite al salir por un borde. |
| `unal_``gfx_result unal_gfx_bg_enable(bool on)` | Muestra u oculta la capa de fondo. | `on` | `UNAL_``GFX_OK` | Oculta = totalmente transparente. |

**HUD (fijo)**

| Función | Descripción | Argumentos | Retorna | Efectos |
| --- | --- | --- | --- | --- |
| `unal_``gfx_result unal_gfx_hud_load_map(const unal_gfx_rect* region, unal_gfx_rom_addr src)` | Carga un bloque del HUD desde la ROM. | Igual que `unal_``gfx_bg_load_map`, dentro del HUD | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_ARG` | Encola la DMA a la memoria de mapas. |
| `unal_``gfx_result unal_gfx_hud_set_tile(uint16_t tx, uint16_t ty, unal_gfx_tile_entry e)` | Cambia una celda del HUD desde la CPU. | `tx` < `UNAL_``GFX_HUD_MAP_W`, `ty` < `UNAL_``GFX_HUD_MAP_H`; `e`: entrada | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_ARG` | Una celda del HUD; tile 0 o índice 0 = transparente. |
| `unal_``gfx_result unal_gfx_hud_fill(const unal_gfx_rect* region, unal_gfx_tile_entry e)` | Llena un bloque del HUD con la misma entrada. | `region` en tiles, `NULL` = HUD completo; `e`: entrada | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_ARG` | Ese bloque del HUD; útil para borrar con tile 0. |
| `unal_``gfx_result unal_gfx_hud_enable(bool on)` | Muestra u oculta el HUD. | `on` | `UNAL_``GFX_OK` | Oculto = totalmente transparente. |

Texto en pantalla: se resuelve cargando una fuente como tiles y escribiendo celdas del HUD; no requiere funciones extra.

## 9. Consultas y errores

| Función | Descripción | Argumentos | Retorna | Efectos |
| --- | --- | --- | --- | --- |
| `unal_``gfx_result unal_gfx_get_info(unal_gfx_info* out)` | Informa límites y uso actual. | `out`: estructura a llenar | `UNAL_``GFX_OK`, `UNAL_``GFX_ERR_INVALID_ARG` si `out` es nulo | Ninguno. |
| `const char* unal_gfx_result_str(unal_gfx_result r)` | Texto legible de un código de resultado, para logs. | `r`: código | Cadena estática | Ninguno. |

**Ejemplo de uso**

```c
#include "unal_gfx.h"
#include "rom_recursos.h"   // direcciones unal_gfx_rom_addr generadas por la herramienta de assets

unal_gfx_init();
unal_gfx_palette_load(0, 16, ROM_PALETA);
unal_gfx_tileset_load(0, 64, ROM_TILES_NIVEL1);
unal_gfx_bg_load_map(&(unal_gfx_rect){0, 0, 64, 64}, ROM_MAPA_NIVEL1);

unal_gfx_image hoja;   unal_gfx_image_load(ROM_HOJA_JUGADOR, 128, 128, &hoja);
unal_gfx_sprite jug;   unal_gfx_sprite_create(hoja, &jug);
unal_gfx_sprite_set_visible(jug, true);

while (jugando) {
    leer_eventos_botones();                           // banderas que dejaron las interrupciones
    actualizar_logica();
    unal_gfx_frame_begin();
    unal_gfx_clear(UNAL_GFX_COLOR_KEY);                         // framebuffer transparente: se ve el fondo
    unal_gfx_fill_circle(px, py, 6, UNAL_GFX_RGB(255, 200, 0)); // efecto dibujado
    unal_gfx_sprite_set_src(jug, &(unal_gfx_rect){cuadro * 16, 0, 16, 16});
    unal_gfx_sprite_set_pos(jug, jx, jy);
    unal_gfx_bg_set_scroll(camara_x, camara_y);
    unal_gfx_hud_set_tile(1, 1, UNAL_GFX_TILE(TILE_DIGITO_0 + vidas, 0));
    unal_gfx_present();
}
```

## 10. Pendiente por definir

Puntos abiertos que pueden agregar o cambiar funciones; conviene cerrarlos antes de congelar la versión 1.0.

- [x] **Transparencia parcial (alpha)**: hoy solo hay color clave, todo o nada.Respuesta: Todo o nada
- [x] **Límites definitivos**: `UNAL_``GFX_MAX_SPRITES`, `UNAL_``GFX_MAX_IMAGES`, `UNAL_``GFX_MAX_TILES`, tamaño del mapa de fondo, `UNAL_``GFX_MAX_IMAGE_DIM` (hoy 360). Respuesta : usar el propuesto
- [x] **Valor de **`UNAL_``**GFX_COLOR_KEY**`: el color elegido no se podrá usar como color visible.Respuesta : usar el propuesto
- [x] **Orden sprites vs. dibujo inmediato**: hoy los sprites siempre quedan encima de los comandos del frame. ¿Hace falta dibujar algo por encima de los sprites fuera del HUD? Respuesta: Queda como idea, no sera implementado
- [x] **Lectura de píxeles desde la CPU** (`unal_``gfx_image_read`), por ejemplo para colisiones por píxel o capturas. Respuesta: No
- [x] **Escritura de píxeles desde la CPU** a una imagen, sin pasar por la ROM, para datos generados en tiempo de ejecución. Respuesta: Si, para generar imagenes en ejecución y/o modificar las cargadas desde la ROM
- [x] **Aviso de vsync**: ¿basta con `unal_``gfx_wait_vsync` o se necesita un callback? Respuesta: Considerar unicamente wait\_vsync
- [ ] **Formato de la ROM de recursos** y herramienta de assets: cómo se empaquetan imágenes, tiles, paletas y mapas, y cómo se genera el encabezado con sus direcciones. Respuesta: Se debe hablar con el equipo de juegos, ya estaban usando una aproximación
- [ ] **Asignador de la memoria de video**: qué hacer con la fragmentación al cargar y liberar imágenes de distinto tamaño. Respuesta: Pendiente importante
- [x] **Formato de las entradas de hardware** (sprites, mapas, tileset): el de la sección 3 es una propuesta. Respuesta: Se acepta usar el propuesto
- [ ] **Presupuesto del blitter por frame**: cómo lo reporta el backend de PC para que el juego no exceda lo que el hardware alcanza a dibujar. Respuesta: Pendiente importante
