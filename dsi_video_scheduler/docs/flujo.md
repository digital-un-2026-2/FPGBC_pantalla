# Contrato del flujo propuesto

Este documento acompaña las dos páginas de `DSI_VIDEO_SCHEDULER.drawio`.
Describe operaciones y responsabilidades. El [datapath propuesto](datapath.md)
lo concreta en páginas 3–6 del mismo editable; la [FSM propuesta](fsm.md)
está en páginas 7–8. El RTL y el control CSR por PC están implementados en
la [integración de pantalla](../../dsi_display/README.md). Este documento conserva
la propuesta RISC-V; el firmware y la secuencia validada del panel siguen pendientes.

## Firmware y LiteX

1. Arrancar RISC-V con memoria y firmware propios de un futuro target LiteX.
   Los targets actuales son SoCMini sin CPU; `display` controla la cadena por PC.
2. Mantener vídeo detenido y autorización del panel invalidada. Seleccionar
   un perfil de panel y PHY adecuado al destino. En hardware debe estar
   caracterizado; un perfil sintético solo sirve para simulación.
3. Inicializar mediante comandos LPDT y esperas de software, comprobando
   los fallos locales y la finalización del envío antes de continuar.
   Los comandos/retardos exactos dependen de la variante de panel.
4. Con enlace libre, seleccionar perfil y VC, y solicitar su validación.
   El datapath concreta las dimensiones y el calendario como constantes de
   perfiles compatibles con el generador elaborado, seleccionadas mediante CSR.
   Solo después autorizar el panel y emitir START. Rechazar configuración
   mientras haya vídeo activo; para cambiarla, detener primero.
5. Supervisar estado y eventos. STOP queda pendiente hasta terminar el cuadro
   y liberar el enlace; los comandos de inicialización no compiten con vídeo.
6. Ante fallo, bloquear inicios, invalidar autorización y conservar causa.
   Recuperar mediante reset coordinado, nueva configuración e inicialización.

CSR propuestos a nivel funcional: configuración y APPLY, START, STOP,
panel_initialized, reset coordinado; lectura de config_ok, running, stopped,
frame_count, error y error_cause. Eventos retenidos o contadores evitan perder
pulsos durante el sondeo por software. Nombres, anchuras y direcciones no son
la interfaz implementada: el mapa actual está en `dsi_display/README.md`.
El mailbox implementado transfiere órdenes y snapshots entre CSR y vídeo.

## Planificador RTL

La configuración activa se captura al aceptar START y permanece fija durante
la ejecución. Un cuadro inicia una transferencia de `dsi_test_pattern` mediante
su handshake. El calendario decide esperas, paquetes y fin de cuadro.
El datapath propone una ROM constante de eventos WAIT/RGB/END para el primer
recorrido RGB. Su contenido, certificación temporal y ampliaciones para los
eventos exigidos por el modo real del panel siguen pendientes.

Para cada línea RGB888 se ofrece un descriptor al preparador largo con
`cmd_dt=0x3E`, `cmd_wc=3*WIDTH` y VC del perfil. Descriptor y valid permanecen
estables hasta aceptación. El payload llega directamente de la fuente;
solo `valid && ready` consume bytes. Verificar exactamente WC bytes, una
marca de fin de línea en el último byte y fin de cuadro en la última línea.
Una discrepancia lleva a fallo. No conectar la marca de fin de línea de la
fuente a `tx_byte_last` del preparador: esta última identifica el CRC final.

La ruta de datos prevista es:

`dsi_test_pattern → dsi_long_packet_tx → dsi_lane_packer → dsi_hs_transport`

El transporte solicita la ruta HS al árbitro; `dphy_hs_tx` ejecuta fases y
`dphy_gowin_tx` adapta la salida física. El planificador no sustituye las FSM
de esos bloques ni conduce directamente pads. El buffer debe contener el
paquete completo antes del envío: para WIDTH=720 son 2166 bytes, dentro de
los 4096 bytes nominales del transporte actual. Validar también límites de
WC, capacidad y restricciones de dimensiones de la fuente. El secuenciador
HS actual rechaza lane parcial: los paquetes usados deben tener longitud par.

El flujo espera tanto el fin del preparador como la finalización HS y la
disponibilidad del transporte antes de avanzar al siguiente paquete. Los
eventos se retienen desde el inicio de cada operación para no perder pulsos:
`packet_done`, `hs_done`, `hs_complete` y `frame_done` pueden ocurrir en
ciclos diferentes. Ninguno implica confirmación de recepción por la pantalla.
El contador de cuadros del planificador avanza después de terminar todos
los eventos del cuadro, incluida la salida del último paquete.

La fuente puede quedar pausada entre líneas. El transporte actual no admite
cargar otro paquete durante el envío HS. La viabilidad temporal debe incluir
el coste de preparar, almacenar, transmitir y liberar cada paquete; una
configuración inviable se rechaza antes de START. Si durante la ejecución
se pierde un plazo del calendario, se registra fallo y se bloquean nuevos
paquetes. Un fallo del planificador no debe cortar arbitrariamente los pads:
la salida segura y recuperación corresponden a la cadena PHY existente.

Prioridad global: reset coordinado, fallo/aborto y luego avance normal.
STOP se conserva hasta un límite de cuadro con enlace libre; no es aborto.
Las esperas por ready o finalización no inventan éxito. Un watchdog, si se
añade, requerirá un límite derivado del perfil; aquí no se fija uno arbitrario.

## Dependencias abiertas y comprobación posterior

- Confirmar variante de LCD, Video/Command Mode, resolución, porches,
  eventos DSI, fps y bitrate. El perfil 720×720 del generador es de prueba.
- Definir los eventos no RGB necesarios. `dsi_lp_packet_tx` solo prepara
  escrituras DCS cortas; no es un generador genérico de sincronismos DSI.
  Según el modo elegido harán falta preparadores/adaptaciones adicionales.
- Mantener `PROFILE_OK=0` para hardware hasta caracterizar el perfil Gowin.
- La prueba `test-dsi-display` verifica la cadena real con cuadros repetidos,
  STOP, rechazo de cambios activos, plazos perdidos, fallos PHY y recuperación
  tras reset. El perfil real requiere además su validación temporal y eléctrica.

El flujo puede diseñarse ahora, pero no constituye validación de tiempos
del panel ni prueba de una integración LiteX/RISC-V ya existente.
