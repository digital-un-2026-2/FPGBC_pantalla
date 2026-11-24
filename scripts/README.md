# Herramientas de inicialización LP

| Archivo | Función |
|---|---|
| `compare_lp_captures.py` | Compara bytes, estados, tiempos y actividad previa de las capturas LP |
| `kvdat_lp.py` | Lee el formato Kingst observado y combina los estados P/N |
| `pack_lp_checked.py` | Ejecuta el empaquetador con auditoría de pads y fusibles |
| `test_compare_lp_captures.py` | Pruebas sintéticas del lector y el comparador |

## Comparar capturas

Los `.kvdat` son archivos locales ignorados por Git. Para reproducir la
[comparación de la iteración 2](../docs/comparacion_LP_ITERATION_2.md), colocar
en la raíz `LP_ITERATION_2.kvdat`, `MIPI_DSI.kvdat` y
`LP_MIPI_DSI_NEW.kvdat`:

```sh
mkdir -p build/lpdt_iteration_02_reset
pixi run python scripts/compare_lp_captures.py > build/lpdt_iteration_02_reset/capture_comparison.json
```

También se pueden indicar otras capturas:

```sh
pixi run python scripts/compare_lp_captures.py captura.kvdat referencia.kvdat
pixi run test-captures
```

El comparador exige 18 paquetes LPDT y conserva la actividad anterior y los
escapes sin carga por separado. Compara los bytes entre capturas; no certifica
los niveles analógicos ni decodifica vídeo HS. Las pruebas no necesitan
capturas reales ni paquetes adicionales de Python.

## Empaquetado

`pack_lp_checked.py` se integra en el script generado por el
[target LP](../gateware/README.md). Sin `-o`, audita sin escribir bitstream;
con `-o`, solo serializa si pasan los controles. No programa dispositivos.
