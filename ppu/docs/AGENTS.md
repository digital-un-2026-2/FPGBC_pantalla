# Contexto: API gráfica `unal_gfx` (HAL) para consola SoC en FPGA

Resumen de las decisiones tomadas hasta el 2026-11-27. La especificación completa (firmas, argumentos, retornos y efectos) está en la pestaña "Referencia de la API" del documento de diseño; exportarla a Markdown y ponerla junto a este archivo.

## Proyecto
- SoC en FPGA que funciona como consola de juegos 2D. Una API gráfica (`unal_gfx.h`) hace de HAL: el software describe la imagen y el hardware la renderiza.
- Hay dos backends para la misma API:
  - PC sobre raylib, para probar la lógica del juego y ver el resultado.
  - FPGA.
- Objetivos: usar pocos recursos de la FPGA y paralelizar en hardware.

## Hardware
- CPU de 32 bits. Las direcciones son de 32 bits; el direccionamiento es por palabra y queda alineado a 4 B.
- PSRAM SiP de 64 Mbit con bus de 16 bits y controlador ya disponible. Es compartida con el resto del sistema; la API usa unos 4 MB.
- Pantalla MIPI DSI de 2 carriles, 720×720. El límite de ancho de banda de MIPI se analizará más adelante.
- BRAM: 46 bloques de 18.432 bits, con unos 2 KB útiles por bloque.
- Los recursos se cargan por DMA desde una ROM de recursos.

## Arquitectura
- **Blitter + framebuffer doble en PSRAM.** Resolución lógica de 360×360 a 16 bpp (RGB565), escalada ×2 en la salida.
- **Capas, de atrás hacia adelante:**
  1. Color de fondo (backdrop).
  2. Fondo de tiles con scroll.
  3. Framebuffer: primero los comandos de dibujo, luego los sprites.
  4. HUD de tiles fijo.
- **Fondo y HUD** se mezclan al vuelo con el framebuffer al enviar la imagen a la pantalla, sin pasar por la PSRAM.
- **Tiles:** 8×8, 1 B por píxel (índice de paleta). Hay un solo tileset y una sola paleta de 256 colores RGB565, compartidos por fondo y HUD. El índice 0 es transparente.
- **Lo que no se hace:**
  - Rotación y escala.
  - Alpha parcial: la transparencia es todo o nada, con `UNAL_GFX_COLOR_KEY` = 0xF81F.
- **Dibujo** (lo ejecuta el blitter):
  - Píxel, línea, rectángulo y círculo, en contorno y relleno.
  - Degradado lineal de dos colores, horizontal o vertical, en un rectángulo.
  - Blit de imágenes con flip H/V y color clave.
- Los algoritmos de cada operación se definen en el diseño de hardware.

## Nombres de memorias (por convención)
| Memoria | Contenido | Ubicación | Tamaño |
|---|---|---|---|
| ROM de recursos | Assets del juego | ROM externa | Según juego |
| Memoria de video | Imágenes cargadas (hojas de sprites, superficies) | PSRAM | ≈ 3,5 MB |
| Framebuffers A/B | 360×360 RGB565 | PSRAM | 2 × 259.200 B |
| Memoria de paleta | 256 × RGB565 | BRAM/LUT | 512 B, 1 bloque |
| Memoria de tileset | 256 tiles × 64 B | BRAM | 16 KB, 8 bloques |
| Memoria de mapas | Fondo 64×64 + HUD 45×45, 16 bits por celda | BRAM | 6 bloques |
| Memoria de sprites | 128 entradas × 16 B | BRAM | 2 KB, 1 bloque |

En total la API ocupa 16 de los 46 bloques de BRAM.

## Convenciones de la API
- **Coordenadas:** `int16_t`, una por argumento. Solo se empaquetan en las entradas que lee el hardware.
- **Funciones:** devuelven `unal_gfx_result`. `UNAL_GFX_OK` = 0 y los errores son negativos. Una función que falla no cambia nada.
- **Comandos de dibujo y DMA:**
  - Se encolan y se ejecutan en orden.
  - La función retorna al encolar, no al terminar.
  - `unal_gfx_sync` espera a que se vacíe la cola.
- **Frame:**
  - Se abre con `unal_gfx_frame_begin` y se cierra con `unal_gfx_present`.
  - `unal_gfx_frame_begin` no borra el framebuffer.
  - Sprites, scroll, paleta, tileset y mapas se aplican juntos en `unal_gfx_present`.
  - Para sincronizar solo se ofrece `unal_gfx_wait_vsync`, sin callbacks.
- **Un solo contexto de ejecución:** la API se llama solo desde el bucle principal. Las interrupciones (por ejemplo, botones) no llaman `unal_gfx_`; dejan banderas o colas para el bucle.
- **Blit:** modifica el destino de forma permanente; el origen no cambia. Para componer se hace blit sobre una imagen. Los sprites solo leen su imagen.
- **Backend de PC:** la ROM es el mismo binario cargado en RAM, y `unal_gfx_rom_addr` es un desplazamiento dentro de él. Debe avisar cuando el juego exceda un límite del hardware.

## Tipos y handles
- `unal_gfx_color` es `uint16_t` (RGB565).
- `unal_gfx_rect` es `{int16_t x, y, w, h}`.
- `unal_gfx_rom_addr` es `uint32_t`.
- `unal_gfx_tile_entry` es `uint16_t`: bits 0–9 índice de tile, bit 10 flip H, bit 11 flip V, bits 12–15 reservados.
- **Handles** (`unal_gfx_image`, `unal_gfx_sprite`): 32 bits opacos.
  - Bits 0–15: índice en una tabla de descriptores de la HAL.
  - Bits 16–31: generación, para detectar handles viejos.
  - `UNAL_GFX_NONE` = 0 y `UNAL_GFX_SCREEN` = 0xFFFFFFFF.
- **Descriptor de imagen** (≈ 20 B):
  - Dirección base y ancho/alto.
  - Stride.
  - Tamaño del bloque.
  - Número de referencias (impide liberar una imagen en uso).
  - Generación y estado.
- **Descriptor de sprite** (≈ 24 B):
  - Handle de imagen y región origen.
  - Posición, prioridad y flags.
  - Generación y estado.
  - Máscara de las palabras de la entrada de hardware que cambiaron.
- **Entrada de sprite en hardware** (decidido, 4 × 32 bits):

  | Palabra | Contenido |
  |---|---|
  | 0 | x (bits 15–0) y y (bits 31–16) |
  | 1 | Dirección del primer píxel de la región |
  | 2 | Ancho y alto |
  | 3 | Stride (15–0), prioridad (23–16), flip H (24), flip V (25), color clave (26), visible (27) |

- **Mapas:** dos celdas por palabra de 32 bits. El tile *i* empieza en la base del tileset + 64 × *i*.

## Límites (decididos)
| Constante | Valor |
|---|---|
| `UNAL_GFX_PALETTE_SIZE` | 256 |
| `UNAL_GFX_MAX_TILES` | 256 |
| `UNAL_GFX_BG_MAP_W` × `UNAL_GFX_BG_MAP_H` | 64 × 64 (scroll circular) |
| `UNAL_GFX_HUD_MAP_W` × `UNAL_GFX_HUD_MAP_H` | 45 × 45 |
| `UNAL_GFX_MAX_SPRITES` | 128 |
| `UNAL_GFX_MAX_IMAGES` | 256 |
| `UNAL_GFX_MAX_IMAGE_DIM` | 360 |

## Funciones (ver la referencia para el detalle)
- **Ciclo de vida:** `unal_gfx_init`, `unal_gfx_shutdown`, `unal_gfx_frame_begin`, `unal_gfx_present`, `unal_gfx_wait_vsync`, `unal_gfx_sync`, `unal_gfx_frame_count`.
- **Imágenes:** `unal_gfx_image_create(w,h,&out)`, `unal_gfx_image_load(rom,w,h,&out)`, `unal_gfx_image_load_region(img,rect,rom)`, `unal_gfx_image_write(img,rect,pixels)`, `unal_gfx_image_free`, `unal_gfx_image_size`.
- **Dibujo:** `unal_gfx_set_target`, `unal_gfx_set_clip`, `unal_gfx_clear`, `unal_gfx_draw_pixel`, `unal_gfx_draw_line`, `unal_gfx_draw_rect`, `unal_gfx_fill_rect`, `unal_gfx_fill_gradient(rect,a,b,UNAL_GFX_GRAD_H|V)`, `unal_gfx_draw_circle`, `unal_gfx_fill_circle`, `unal_gfx_blit(src,src_rect,x,y,flags)`.
- **Sprites:** `unal_gfx_sprite_create`, `unal_gfx_sprite_destroy`, `unal_gfx_sprite_set_image`, `unal_gfx_sprite_set_src`, `unal_gfx_sprite_set_pos`, `unal_gfx_sprite_set_flags`, `unal_gfx_sprite_set_priority`, `unal_gfx_sprite_set_visible`.
  - Los sprites se dibujan en `unal_gfx_present`, encima de los comandos del frame.
  - `unal_gfx_sprite_set_image` devuelve `UNAL_GFX_ERR_INVALID_ARG` si la región actual no cabe en la nueva imagen.
- **Paleta, tiles y fondo:** `unal_gfx_palette_load(first,count,rom)`, `unal_gfx_palette_set(index,color)`, `unal_gfx_tileset_load(first,count,rom)`, `unal_gfx_set_backdrop`, `unal_gfx_bg_load_map(rect,rom)`, `unal_gfx_bg_set_tile`, `unal_gfx_bg_fill`, `unal_gfx_bg_set_scroll`, `unal_gfx_bg_enable`.
  - En las funciones de mapa, `src` apunta a un arreglo de `unal_gfx_tile_entry` fila por fila.
- **HUD:** `unal_gfx_hud_load_map`, `unal_gfx_hud_set_tile`, `unal_gfx_hud_fill`, `unal_gfx_hud_enable`. El texto se dibuja como tiles en el HUD.
- **Consultas:** `unal_gfx_get_info`, `unal_gfx_result_str`.

## Pendientes abiertos
1. **Asignador de la memoria de video:** cómo manejar la fragmentación. **Importante.**
2. **Presupuesto del blitter por frame:** cómo lo reporta el backend de PC. **Importante.**
3. **Formato de la ROM de recursos y herramienta de assets:** acordarlo con el equipo de juegos, que ya usa una aproximación.

## Descartado o resuelto
- No habrá lectura de píxeles desde la CPU.
- No habrá dibujo por encima de los sprites fuera del HUD (queda solo como idea).
- No hay callback de vsync.
- El límite de MIPI se analizará después.

## Hoja de ruta
- **Software:**
  1. `unal_gfx.h` y backend raylib con verificador de límites.
  2. Herramienta de assets.
  3. Modelo de referencia en C bit-exacto.
  4. Driver FPGA.
  5. Demos.
- **Hardware:**
  1. Árbitro de PSRAM.
  2. Temporización 720×720 y salida MIPI con escalado ×2.
  3. Framebuffer doble y relleno.
  4. Cola de comandos y blitter.
  5. Sprites.
  6. Fondo y HUD.
  7. Formas y degradado.
  8. Verificación contra el modelo C en cada paso.
