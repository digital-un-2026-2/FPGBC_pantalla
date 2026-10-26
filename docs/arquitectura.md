# Arquitectura y siguientes etapas

[Inicio](../README.md) · [Hardware](hardware.md) · [LPDT](../motor_lpdt/docs/lpdt.md)

## Separación funcional prevista

```text
RISC-V ──► Control / cola de comandos ─────────┐
                                             ▼
PPU ──► Adaptador ──► Buffers ──► Planificador DSI
                                             │
                                  Packing / paquetes / ECC / CRC
                                             │
                                  Controlador de transporte
                                    │                 │
                                Motor LPDT     Multilane / HS
                                    └────────┬────────┘
                                    Drivers / tiempos D-PHY
                                             │
                                    Red eléctrica FPGBC
                                             │
                                          Pantalla
```

Es una arquitectura prevista, no una lista de módulos implementados. Existen
el motor LPDT y sus bloques de apoyo; PPU, bus del SoC y cadena de síntesis
siguen sin definirse. El RISC-V previsto no implica un procesador físico dedicado
ni conocimiento de la arquitectura del firmware original.

El software decide comandos/configuración; el hardware garantiza codificación
y tiempos. Los buffers desacoplan producción y consumo, pero una FIFO no
corrige una diferencia permanente de tasas medias. Framebuffer, repetición
de cuadros y política de underflow/overflow siguen pendientes.

## Paquetes para etapas posteriores

```text
Corto: [Data ID][Data 0][Data 1][ECC]
Largo: [Data ID][WC low][WC high][ECC][Payload: WC bytes][CRC low][CRC high]
```

- Data ID: VC en bits 7:6 y tipo de dato en 5:0.
- WC cuenta bytes del payload, no píxeles; un paquete largo ocupa WC + 6 bytes.
- ECC protege los tres primeros bytes; no es una suma de bytes.
- Los paquetes cortos no llevan CRC. El CRC de 16 bits protege el payload de
  paquetes largos de píxeles; otros tipos requieren estudiar sus reglas.
- Un burst HS puede contener varios paquetes; no son la misma frontera.
- RGB888 emplea tres bytes por píxel y DT `0x3E`; aún no está seleccionado.
- Las lanes distribuyen bytes, no componentes R/G/B por separado.

## Pendientes, en orden

1. **Cerrar el motor LPDT:** contrato de interfaz, solicitud sostenida y
   decodificador independiente por transiciones P/N. La prueba actual usa
   posiciones temporales conocidas; no es un receptor LPDT general.
2. **Revisar síntesis y temporización:** control en posedge y datapath en
   negedge dejan caminos de medio ciclo (12,5 ns). Faltan restricciones y
   análisis temporal para la FPGA exacta.
3. **Validar LP en placa:** referencia completa de FPGA, revisión de PCB,
   medidas de VCCIO, niveles, flancos y habilitaciones de drivers.
4. **Supervisor e inicialización:** reposo inicial, CLK/D1, recuperación tras
   abortos, secuencia específica del panel y esperas DCS configurables.
5. **Transporte HS:** primitivas, PLL, serializadores, reloj, transiciones LP/HS
   y distribución multilane. Los 40 MHz de control no determinan la tasa HS.
6. **Paquetes de imagen:** packing, ECC y CRC con vectores de prueba.
7. **Vídeo:** confirmar variante del panel, modo, formato, porches, refresco y
   velocidad por lane. Presupuestar por línea, con overhead y cambios de modo;
   el promedio por cuadro no basta.
8. **PPU y RISC-V:** interfaz, backpressure, buffers, CDC y diagnóstico;
   evaluar recepción LP/BTA. No asumir AXI, APB, Wishbone ni mapa de registros.

Cada bloque debe documentarse y verificarse antes de integrar el siguiente.
Las pruebas lógicas no certifican la interfaz eléctrica ni la recepción del panel.
