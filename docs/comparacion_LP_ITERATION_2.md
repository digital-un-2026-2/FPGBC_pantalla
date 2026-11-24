# Comparación de todos los niveles LP de la iteración 2

## Resultado

**La inicialización todavía no reproduce toda la forma de onda original.**
Los 18 paquetes y el orden de los estados dentro de las ráfagas coinciden,
pero faltan eventos anteriores a los comandos y difieren las duraciones de
entrada, salida y pausas. No se modificó RTL ni se programó hardware en este análisis.

La bajada de los seis conductores de `LP_ITERATION_2.kvdat` se interpreta
como el reset intencional indicado por el usuario, no como un comando LP.
Ese archivo contiene la medición física de la variante FPGA.
`LP_MIPI_DSI_NEW.kvdat` se analiza como la nueva captura de referencia:
su secuencia y sus tiempos relativos coinciden con el arranque original,
no con la iteración FPGA.

## Archivos y límites de medida

| Archivo | Canales | Muestreo | Duración | Umbral |
|---|---|---:|---:|---:|
| `LP_ITERATION_2.kvdat` | D0P/N, D1P/N, CLK_P/N | 50 MS/s | 2 s | 0,60 V |
| `MIPI_DSI.kvdat` | D0P/N, D1P/N, CLK_P/N | 50 MS/s | 4 s | 0,90 V |
| `LP_MIPI_DSI_NEW.kvdat` | D0P, D0N, D1P | 100 MS/s | 2 s | 0,90 V |

Los metadatos identifican LA1010. El archivo nuevo conserva los nombres
de seis canales en el XML, pero solo habilita y contiene CH0/CH1/CH2.
No permite reconstruir el par D1 ni determinar qué hizo CLK.

SHA-256:

- FPGA: `51b08d9091c54e6f0dbce2589bf0a710715e239241cfca964e4186499f74730a`.
- Original: `3dd920ef4d1f3bb6493952bc9a1b774746324546bcde99afbfb3ef0877a7e855`.
- Nueva: `581cad47a1290d067f70596519ee13cbc02aea7ae51d02bbd0c9f5bc410d6338`.

Son niveles digitalizados: `00` no demuestra que los dos pines estén
conduciendo activamente a cero. El RTL inhibe las salidas durante reset,
por lo que una medida digital baja también puede corresponder a alta
impedancia y a la respuesta de la red externa.
Los pulsos de una muestra se conservan en el análisis, sin atribuirles
automáticamente un significado de protocolo.

## 1. Reset y arranque medidos en la FPGA

Tiempo desde el inicio de `LP_ITERATION_2.kvdat`:

| Intervalo/evento | Observación |
|---|---|
| Antes de 151,49302 ms | Los tres pares están en `11` |
| 151,49302–151,49942 ms | Transiciones durante la bajada de reset; no simultáneas ni limpias en los seis canales |
| 151,49942–359,02764 ms | Los seis canales están bajos: los tres pares en `00`, durante **207,52822 ms** |
| 359,02764 ms | Los seis canales vuelven a alto en la misma muestra |
| 359,02764–359,22792 ms | Los tres pares en `11`, durante **200,28 µs** |
| 359,22792 ms | Entrada Escape del primer comando |
| 624,59548 ms | Final del último comando y regreso a `11` |
| Hasta 2000 ms | Ningún cambio posterior en los seis canales |

Antes del primer comando hay 22 flancos en D0P, 34 en D0N, 14 en D1P,
8 en D1N, 8 en CLK_P y 16 en CLK_N, incluida la recuperación final.
Estos flancos se incluyen en el inventario; no se eliminaron como «ruido».

**No está capturada la entrada del botón de reset.** Por ello, no es
posible medir desde su liberación física ni separar exactamente cuánto
duró la pulsación y cuánto la espera interna. Los 207,52822 ms describen
los conductores, no necesariamente el tiempo de botón pulsado.

## 2. Toda la actividad anterior a los comandos de referencia

Estados escritos como **P,N**.

### Referencia original, seis canales

1. Los tres pares comienzan en `00`. Suben alrededor de **200,0002 ms**.
   Hay pasos intermedios de una muestra por desfase entre P y N.
2. Permanecen en `11` unos **281,485 ms**.
3. A **481,48562 ms**, bajan CLK_P y D1P. D0P también presenta bajadas
   desde **481,48566 ms**, con varios cambios breves antes de estabilizarse.
   D0N, D1N y CLK_N siguen altos en este evento. Por tanto, el estado
   observado es `01`, no un reset simultáneo de los tres pares a `00`.
4. Los P vuelven a alto a **481,49328 ms**. La ventana de CLK_P bajo
   dura **7,66 µs**; D0P y D1P incluyen transitorios al comienzo.
5. Después de **767,96 µs** de `11` desde esa recuperación, D0 hace
   una secuencia corta a **482,26124 ms**:

   ```text
   10 (100 ns) → 00 (100 ns) → 01 (100 ns)
      → 00 (600 ns) → 10 (100 ns) → 11
   ```

   Dura **1,00 µs**. No contiene selector `87` ni bytes DSI; no se
   interpreta como uno de los 18 paquetes ni se le asigna una función
   no demostrada.
6. Tras volver a `11` a **482,26224 ms**, espera **99,99964 ms**.
7. El primer comando comienza a **582,26188 ms**.

### Nueva referencia a 100 MS/s

1. D1P sube a **99,99996 ms**; D0P y D0N suben juntos a
   **100,00007 ms**.
2. D1P baja a **381,39860 ms** y vuelve a alto a **381,40626 ms**.
   Dentro de esa ventana aparece un pulso alto de **10 ns**,
   entre 381,39875 y 381,39876 ms.
3. D0P presenta transitorios entre **381,39904 y 381,39995 ms**,
   después permanece bajo hasta **381,40626 ms**. D0N no cambia.
   Esto confirma que el evento previo no es exclusivo de D0.
4. Después de la recuperación, espera **768,87 µs** y hace la
   secuencia corta a **382,17513 ms**:

   ```text
   10 (100 ns) → 00 (110 ns) → 01 (90 ns)
      → 00 (610 ns) → 10 (100 ns) → 11
   ```

   Dura **1,01 µs**, sin selector ni bytes DSI.
5. Después de volver a `11` a **382,17614 ms**, espera
   **99,99961 ms**.
6. El primer comando comienza a **482,17575 ms**.

### Diferencia de arranque que no explica desplazar las capturas

Desde que D0 alcanza `11` tras el `00` inicial hasta el primer comando:

| Captura | Espera medida |
|---|---:|
| Original | **382,26164 ms** |
| Nueva referencia | **382,17568 ms** |
| FPGA, después del reset observado | **0,20028 ms** |

Las dos referencias tienen una pequeña variación del arranque previo,
pero ambas contienen el evento en P, la secuencia corta y la espera de
100 ms. **La FPGA no contiene ninguno de esos eventos previos.**
Comparar solamente las posiciones absolutas del primer comando en el
archivo ocultaría esta diferencia real.

## 3. Comandos: mismos niveles en el mismo orden, distintas duraciones

En las tres capturas:

- Los 18 paquetes tienen los mismos bytes: selector `87` más
  **204 bytes DSI** en el orden esperado.
- Coincide el orden completo de los **3642 intervalos de estado no LP11**
  dentro de las 18 ráfagas, no solo los bits útiles.
- Todos los intervalos entre comandos están exclusivamente en `11` en D0.
- D1P no cambia durante los comandos en ninguna captura.
  D1N y CLK_P/N tampoco cambian en las dos capturas de seis canales.

### Ejemplo exacto: primer comando

| Tramo observado | FPGA | Original 50 MS/s | Nueva 100 MS/s |
|---|---:|---:|---:|
| Entrada `10` | 100 ns | 100 ns | 100 ns |
| Entrada `00` | 100 ns | 120 ns | 110 ns |
| Entrada `01` | 100 ns | 80 ns | 90 ns |
| **`00` antes del selector** | **100 ns** | **520 ns** | **510 ns** |
| Marca de bit ordinaria `10`/`01` | 100 ns | 80 ns | 90 ns |
| Espacio ordinario `00` | 100 ns | 120 ns | 110 ns |
| **Marca del último bit** | **100 ns** | **180 ns** | **190 ns** |
| **`00` después del último bit** | **100 ns** | **320 ns** | **310 ns** |
| Marca de salida `10` | 100 ns | 100 ns | 100 ns |
| **Ráfaga completa, entrada a retorno `11`** | **14,90 µs** | **15,62 µs** | **15,61 µs** |

No todas las marcas de todos los paquetes tienen exactamente la misma
anchura digitalizada. Por ejemplo, en la FPGA también aparecen 80/120 ns
en algunos tramos a 50 MS/s. Se guardaron los histogramas completos.
Los periodos ordinarios marca+espacio rondan **200 ns** en las tres.
La diferencia sistemática grande se concentra en las esperas de entrada
y salida: aproximadamente **400 + 100 + 200 = 700 ns** adicionales en
la referencia, no en que falten bits.

El umbral de 0,60 frente a 0,90 V y la resolución de 20/10 ns impiden
atribuir automáticamente toda diferencia 80/90/100 ns a la lógica.
No explican los aproximadamente 700 ns por paquete ni el arranque ausente.

### Pausas y deriva

Medidas desde el retorno a `11` hasta la siguiente entrada:

| Pausa | FPGA | Original | Nueva referencia |
|---|---:|---:|---:|
| Ordinaria | 9000,20–9000,22 µs | 8999,76–8999,78 µs | 8999,77–8999,78 µs |
| Larga, tras pasos 4 y 9 | 65000,10–65000,12 µs | 64999,70 µs | 64999,67–64999,68 µs |

Por tanto, la FPGA **acorta las ráfagas pero alarga las pausas**
aproximadamente 0,42–0,46 µs. Los dos errores se compensan parcialmente.

Alineando la entrada del primer comando:

- El inicio del último comando de la FPGA se adelanta **4,76 µs**
  frente al original y **4,66 µs** frente a la captura nueva.
- El final del último comando se adelanta **5,48 µs** y **5,37 µs**,
  respectivamente.

No basta con sumar un retardo al comienzo: persistirían las diferencias
internas de cada ráfaga y de las pausas.

## 4. Después de los 18 comandos

- FPGA: `11` estable hasta el final de la captura; sin pulsos adicionales.
- Original: último retorno a `11` a **847,63492 ms**.
  CLK_P baja a **853,63486 ms**, CLK_N a **853,63494 ms**.
  D0/D1 empiezan otra actividad a **854,63486 ms**, aproximadamente
  **7 ms** después del último paquete.
- Nueva referencia: último retorno a `11` a **747,54868 ms**.
  D0 y D1P empiezan otra actividad a **754,54863 ms**,
  **6,99995 ms** después.

Esa actividad posterior presenta niveles compatibles con la envolvente
ya analizada en las capturas de vídeo; no es otra serie de comandos
Escape/LPDT ni demuestra por sí misma un enlace HS válido.
Para el objetivo exclusivamente LPDT, se registra como frontera posterior,
no como una orden de implementar vídeo.

## Reproducción del análisis

```sh
mkdir -p build/lpdt_iteration_02_reset
pixi run python scripts/compare_lp_captures.py > build/lpdt_iteration_02_reset/capture_comparison.json
```

Las tres capturas son locales y están ignoradas por Git. Ver las
[herramientas LP](../scripts/README.md) para indicar otros archivos.

El JSON conserva todos los intervalos previos por par, los flancos previos
por canal, cada paquete, histogramas de niveles/duraciones, pausas,
comparaciones y contadores de cambios posteriores hasta el fin de archivo.
La marca final de adquisición no se cuenta como flanco.

Para la siguiente corrección hay que decidir cómo reproducir los eventos
previos comunes a las referencias, extender los tramos de entrada/salida
y ajustar las pausas. No convertir los pulsos breves no identificados en
comandos DSI nuevos ni intentar copiar tiempos de alimentación desconocidos.
