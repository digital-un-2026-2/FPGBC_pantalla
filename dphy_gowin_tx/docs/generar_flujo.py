"""Genera el único Draw.io: interfaces, flujo y datapath."""
from pathlib import Path
import xml.etree.ElementTree as E
from diagramas import Page
from generar_datapath import add_datapath
from generar_fsm import add_fsm

OUT=Path(__file__).resolve().parent
doc=E.Element('mxfile',host='app.diagrams.net')
p=Page(doc,'interconexion','01 · INTERCONEXIÓN','DPHY_GOWIN_TX · INTERCONEXIÓN ENTRE MÓDULOS',
       'Las flechas identifican buses de la tabla inferior. _s = secuenciador lógico; _p = salida física programada / retorno al árbitro.',height=1800)
p.reg('transport','dsi_hs_transport\nPaquete completo → palabras HS',50,230,350,140)
p.reg('arb','dphy_mode_ctrl\nÚnico árbitro LP / HS',600,230,400,140)
p.reg('seq','dphy_hs_tx\nSecuenciador lógico existente\nGenera fases, tramas y Trail',600,540,400,170)
p.reg('lp','dsi_lpdt_bridge\nIncluye dphy_lpdt_tx\nLP_STATE = estado_D0',50,540,350,170)
p.reg('wrap','dphy_gowin_tx\nCaptura + serializadores\nRetardo común L + drivers\nSupervisor de reloj/reset',1230,460,480,250)
p.text('panel','12 pines FPGA → red de la placa\n6 conductores → pantalla\nLP: CLK/D1/D0, P/N\nHS: CLK/D1/D0, P/N',1230,820,480,130)
p.wire('transport','arb','T_REQ [3] / T_ACK [3]',ports='startArrow=block;startFill=1;')
p.wire('transport','seq','HS_WORD [20]',[(450,300),(450,625)])
p.wire('arb','seq','HS_CMD [5]',ports='exitX=0.5;exitY=1;entryX=0.5;entryY=0;')
p.wire('lp','arb','LP_REQ / LP_DONE [2]',[(430,625),(430,430),(800,430)],ports='entryX=0.5;entryY=1;')
p.wire('arb','lp','lp_grant [1]',[(490,300),(490,480),(225,480)],ports='exitX=0;exitY=0.5;entryX=0.5;entryY=0;')
p.wire('lp','wrap','LP_STATE [2]',[(450,780),(1150,780),(1150,660)],ports='entryX=0;entryY=0.8;')
p.wire('seq','wrap','SEQ_CMD [32]')
p.wire('arb','wrap','lp_grant + phy_abort [2]',[(1090,300),(1090,485)],ports='entryX=0;entryY=0.1;')
p.wire('wrap','arb','PHY_FB [6]',[(1760,585),(1760,190),(800,190)],ports='entryX=0.5;entryY=0;')
p.gate('errors','G_ERR · OR [1]\ntransport.hs_error | seq.phy_error\n| wrapper.clock_fault',1230,230,480,140)
p.wire('errors','arb','hs_error [1]',ports='exitX=0;exitY=0.5;entryX=1;entryY=0.2;')
p.wire('wrap','errors','clock_fault [1]',ports='exitX=0.75;exitY=0;entryX=0.75;entryY=1;')
p.wire('seq','errors','phy_error [1]',[(1120,685),(1120,420),(1350,420)],ports='exitX=1;exitY=0.85;entryX=0.25;entryY=1;')
p.wire('transport','errors','transport.hs_error [1]',[(225,175),(1170,175),(1170,265)],ports='exitX=0.5;exitY=0;entryX=0;entryY=0.25;')
p.wire('wrap','panel','LP_PAD [6] + HS_PAD [6]',ports='exitX=0.5;exitY=1;entryX=0.5;entryY=0;')
p.table('buses',[
 ('Bus','Campos y sentido exacto'),
 ('HS_WORD [20]','transporte → secuenciador: hs_word_data[16], keep[2], valid, last. hs_grant viene del árbitro.'),
 ('T_REQ [3] / T_ACK [3]','→ árbitro: hs_req, hs_done, hs_data_ready. Retorno: hs_req_ready, hs_grant, hs_complete. Error por G_ERR.'),
 ('HS_CMD [5]','árbitro → secuenciador: clk_start_req, data_start_req, data_stop_req, clk_stop_req, hs_grant.'),
 ('SEQ_CMD [32]','→ wrapper: frame[16], kind[2], HS_ON[2], toggle, LP[6], ACK_s[4], local_stop_s.'),
 ('PHY_FB [6]','→ árbitro: ACK_p[4], stop_ready, pll_ready. clock_fault va por separado a G_ERR.'),
 ('LP_REQ / LP_DONE','puente → árbitro: lp_req, tx_done → lp_done. lp_grant → permiso_arranque del puente y M0 del wrapper.'),
 ('Errores (OR externo)','árbitro.hs_error = transporte.hs_error | secuenciador.phy_error | wrapper.clock_fault.'),
 ('Reset y reloj','ref_clk=clk40 → wrapper; byte_clk + rst_byte → cadena común. rst es reset coordinado externo.'),
 ('Salidas del árbitro','lp_complete / hs_complete → productores. El wrapper no genera esos pulsos ni recibe hs_word_last.')
],50,1000,[300,1400],65,17)

p=Page(doc,'flujo-general','02 · FLUJO · General','DPHY_GOWIN_TX · FLUJO GENERAL / LPDT',
       'Una caja es una operación, no necesariamente un estado o un ciclo. Captura continua durante reposo, preparación y retorno LP.',height=1900)
p.process('start','INICIO / RESET COORDINADO\nrst=1; HS_OE=000; invalidar tubería; bloquear ACK_p y stop_ready.',200,190)
p.process('release','¿STATE=WAIT_LOCK, B=1,\nrst=0 y F=0?',260,350,530,140,'decision')
p.chain('start','release');p.wait('release',900,350)
p.process('boot','ENTRAR RELEASE; RUN_STARTED←1; BOOT_ALLOWED←0.\nRELEASE_SAFE=G_RELEASE durante ese ciclo REF.\nTras SER_READY_B=1: RUN_B=1, RST_PIPE=0 y LD_CMD=1.',200,560,650,140)
p.wire('release','boot','Sí',flow=True)
p.process('valid','¿V_P=1?\nL capturas de control válidas',260,750,530,140,'decision');p.wire('boot','valid',flow=True);p.wait('valid',900,750)
p.process('run','OPERACIÓN CONTINUA\nCMD_p = CMD_s retardado L ciclos.\nAplicar LP/HS y ACK según las láminas DATAPATH.',200,960,650,120)
p.wire('valid','run','Sí',flow=True)
p.process('owner','¿lp_grant=1?',260,1150,530,140,'decision');p.wire('run','owner',flow=True)
p.process('lp','CAPTURAR LPDT\nM0 selecciona estado_D0; capturar también LP_OWNER=1.\nHS permanece apagado por las órdenes del secuenciador.',1030,1140,650,130)
p.wire('owner','lp','Sí',ports='exitX=1;exitY=0.5;entryX=0;entryY=0.5;')
p.process('lpdone','ÁRBITRO: ¿lp_done=1?\nDesde bridge.tx_done',1090,1320,530,140,'decision')
p.wire('lp','lpdone',flow=True);p.wait('lpdone',1740,1320)
p.process('lpend','FIN LP LÓGICO → árbitro.lp_done\nSeguir capturando: D0=11 y LP_OWNER=0\ndeben alcanzar la salida.',1030,1570,650,110)
p.wire('lpdone','lpend','Sí',flow=True)
p.process('stoptest','¿C_STOP=1?',260,1400,530,140,'decision')
p.process('idle','RETORNO FÍSICO PROGRAMADO\nstop_ready=1; el árbitro puede producir lp_complete\no conceder el siguiente modo.',200,1660,650,110)
p.wire('owner','stoptest','No · ver flujo HS',flow=True)
p.wire('lpend','stoptest','Esperar salida',[(960,1625),(960,1470)],ports='exitX=0;exitY=0.5;entryX=1;entryY=0.5;')
p.wire('stoptest','idle','Sí',flow=True)
p.wire('stoptest','run','No · seguir capturando',[(150,1470),(150,1040)],ports='exitX=0;exitY=0.5;entryX=0;entryY=0.7;')
p.wire('idle','run','Siguiente ciclo',[(110,1715),(110,1010)],ports='exitX=0;exitY=0.5;entryX=0;entryY=0.3;')
p.text('global','PRIORIDAD GLOBAL\nrst, phy_abort o pérdida de LOCK → recuperación (página 4).\nNo usar busy del puente LPDT para stop_ready.',1030,250,650,180)
p.table('ops',[
 ('Control / condición','Definición'),
 ('LD_CMD','1 cada ciclo de byte_clk con RUN_B=1; captura también durante LP-11 y HS apagado.'),
 ('RST_PIPE','rst_byte | phy_abort | !RUN_B. Prioridad sobre LD_CMD; invalida todas las etapas.'),
 ('V_P','Validez de la última etapa de control; no es valid de payload.'),
 ('PROFILE_OK','Constante del perfil físico. BOOT_ALLOWED es decodificación de STATE, sin otro registro.'),
 ('B / F','Guardas de la FSM (pág. 8). B=PROFILE_OK & LOCK_SYNC & !ABORT_REF & !EV_REF; F tiene prioridad.')
],1030,520,[170,480],100,17)

p=Page(doc,'flujo-hs','03 · FLUJO · HS','DPHY_GOWIN_TX · FLUJO DE RÁFAGA HS',
       'Izquierda: operaciones de dphy_hs_tx. Derecha: efecto del wrapper. Datos, LP/HS y confirmaciones se desplazan conjuntamente L ciclos.',height=2000)
rows=[
 ('clk','ÁRBITRO → clk_start_req\nSecuenciador: CLK-LPX → PREPARE → ZERO → PRE.\nCLK HS-0 antes de empezar a oscilar.',
  'phy-clk','M1=00 durante Zero/Trail; M1=AA al oscilar.\nS2 serializa; CLK_OE sigue clk_on retardado.\nclk_prepared_p = SAFE & ACK_P[0].'),
 ('data','ÁRBITRO → data_start_req\nSecuenciador: DATA-LPX → PREPARE → ZERO.\nEsperar primera palabra antes de lanzar Sync.',
  'phy-data','Retardar DATA_ON, LP_D0/D1 y kind con el dato.\ndata_prepared_p = SAFE & ACK_P[1].\nDespués el árbitro concede hs_grant.'),
 ('sync','PRIMERA PALABRA CAPTURADA\nSecuenciador: frame=B8B8, kind=01.\nDespués payload, kind=10, sin huecos.',
  'phy-sync','R_FRAME → S0/D0 y S1/D1.\nSync y payload recorren el mismo camino.\nNo insertar etapas distintas según kind.'),
 ('last','ÚLTIMA PALABRA\nTransporte → hs_done; árbitro retira grant\ny activa data_stop_req. Secuenciador drena ACTIVE.',
  'phy-last','Capturar y serializar todas las tramas pendientes.\nNo usar hs_grant como enable del serializador.\nOSER8 no tiene un puerto DONE.'),
 ('trail','SECUENCIADOR → kind=11\nframe ya contiene Trail por lane.\nDespués DATA_ON=0, LP_D0/D1=11; cumplir Exit.',
  'phy-trail','Trail sigue al último bit payload.\nLP y OE llegan con el mismo retardo L.\ndata_stopped_p = SAFE & ACK_P[2].'),
 ('post','ÁRBITRO → clk_stop_req\nSecuenciador satisface POST desde fin de Trail\nde datos; después CLK-TRAIL y CLK-EXIT.',
  'phy-post','Sin segundo contador POST en el wrapper.\nEl retardo común conserva los intervalos.\nclk_stopped_p = SAFE & ACK_P[3].'),
 ('finish','SECUENCIADOR → local_stop_s=1\nCLK/D0/D1 en LP-11; HS apagado.',
  'phy-finish','C_STOP=1 → stop_ready=1.\nÁrbitro emite hs_complete tras el retorno conjunto.\nNo confirma recepción del panel.')]
for i,(a,at,b,bt) in enumerate(rows):
 y=210+i*225
 p.process(a,at,80,y,710,145);p.process(b,bt,1010,y,710,145)
 p.wire(a,b,'Retardo L',ports='exitX=1;exitY=0.5;entryX=0;entryY=0.5;')
 if i:p.wire(rows[i-1][0],a,flow=True);p.wire(rows[i-1][2],b,flow=True)
p.text('note','keep=11 se comprueba en el secuenciador. El wrapper no añade relleno a paquetes impares.\nReset, phy_abort o pérdida de PLL → página 4. El perfil debe demostrar latencia común hasta los pads; de lo contrario esta arquitectura no es aplicable.',80,1810,1640,100)

p=Page(doc,'flujo-fallo','04 · FLUJO · Recuperación','DPHY_GOWIN_TX · RESET, ABORTO Y PÉRDIDA DE PLL',
       'La inhibición final no espera a FCLK. Recuperación por reset coordinado; clear_error del árbitro no recupera el wrapper.',height=1800)
p.process('event','DESDE CUALQUIER PUNTO\nrst=1, phy_abort=1, LOCK_RAW=0, UC_BLOCK=1 o EV_RAW=1',220,200,650,110,'fault')
p.process('inhibit','ASERCIÓN PRIORITARIA\nINHIBIT←1 (asíncrono); HS_OE←000.\nACK_p←0000; stop_ready←0; aplicar LP_BLOCK.',220,390,650,130,'fault')
p.process('flush','INVALIDAR / DESCARTAR\nRST_PIPE=1; mantener SER_RESET=1.\nCancelar operación; no generar complete.',220,600,650,120,'fault')
p.process('reason','¿Pérdida de LOCK\ndespués de RUN_STARTED=1?',270,800,550,140,'decision')
p.process('cause','CLOCK_FAULT←1\nConservar hasta rst.\nOR externo → árbitro.hs_error.',1050,800,650,130,'fault')
p.process('reset','¿Nuevo reset coordinado\ncompletado por el sistema?',270,1050,550,140,'decision')
p.chain('event','inhibit','flush','reason')
p.wire('reason','cause','Sí',ports='exitX=1;exitY=0.5;entryX=0;entryY=0.5;')
p.wire('reason','reset','No',flow=True)
p.wire('cause','reset','También esperar reset',[(1375,990),(545,990)],ports='exitX=0.5;exitY=1;entryX=0.5;entryY=0;')
p.wait('reset',920,1050,'No · bloqueo')
p.process('restart','REINICIAR TODA LA CADENA\nTransporte, árbitro, secuenciador y ruta LPDT.\nVolver al arranque: LOCK estable → liberar resets → llenar tubería.',220,1310,650,130)
p.wire('reset','restart','Sí',flow=True)
p.table('priority',[
 ('Prioridad','Efecto'),
 ('rst','Limpiar CLOCK_FAULT y RUN_STARTED; mantener INHIBIT hasta arranque completo.'),
 ('phy_abort','Inhibir HS e invalidar tubería. Exigir reset; no crea CLOCK_FAULT por sí solo.'),
 ('!LOCK_RAW','Inhibir inmediatamente. Registrar CLOCK_FAULT si RUN_STARTED ya era 1.'),
 ('RELEASE_SAFE','Solo supervisor tras reset y LOCK estable. La salida sigue bloqueada si V_P=0.')
],1050,230,[160,490],100,17)
p.text('lp','RAMAS LP DURANTE RECUPERACIÓN\nLP_EN=P_LP_BLOCK_EN; LP_DAT=P_LP_BLOCK_DATA.\nModelo: EN=000000 (alta impedancia).\nNo forzar LP-11 contra un motor activo.\nEl perfil eléctrico final requiere validación de la placa.',1050,1130,650,200)

add_datapath(doc)
add_fsm(doc)
doc.set('pages',str(len(doc.findall('diagram'))))
E.indent(doc,space='  ')
E.ElementTree(doc).write(OUT/'DPHY_GOWIN_TX.drawio',encoding='utf-8',xml_declaration=True)
print(OUT/'DPHY_GOWIN_TX.drawio')
