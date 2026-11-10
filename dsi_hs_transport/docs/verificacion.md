# Plan de verificación previo a RTL

- Monitor público: guardar entradas aceptadas y comparar palabras/máscaras de
  salida, last y continuidad por ciclo; done exactamente después de last.
- Profundidades 1, 3 y 2048, capacidad exacta, paquete parcial, exceso y máscaras
  00/10/01 no final; petición mantenida, concesión demorada y liberación tardía.
- Reset en todas las fases y aborto antes/durante transferencia; primera causa
  persistente, ningún éxito tras aborto y recuperación con reset coordinado.
- Integración con preparadores corto/largo y packer reales, árbitro LP/HS,
  modelo PHY de latencia variable y competencia con LPDT real.
- Comparar bytes aceptados por packer con salida HS reconstruida, incluidos
  ECC/CRC, paquetes consecutivos y carga útil de 2160 bytes.
- Elaboración Icarus, simulaciones autocontenidas con watchdog y Yosys:
  sin latches/conexiones incorrectas, RAM inferida y reloj único.
- Regresiones de módulos existentes. Registrar resultados reales, sin convertir
  una prueba lógica en afirmación de conformidad eléctrica o caudal de vídeo.
