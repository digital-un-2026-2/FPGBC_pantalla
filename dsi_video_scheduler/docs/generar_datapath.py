"""Cuatro vistas de datapath. Page es el renderizador compartido con el flujo."""


def base(Page, name, title, subtitle, height=2400):
    p = Page(name, height)
    p.node('title', title, 60, 20, 1680, 70, 'text')
    p.node('subtitle', subtitle, 60, 100, 1680, 100, 'text')
    p.node('footer', 'PROPUESTA · Registros en ↑clk; rst síncrono prioritario. LD=0 conserva Q.\nBuses [n]; controles discontinuos. Redes con el mismo nombre se conectan entre páginas. Ecuaciones: datapath.md.',
           60, height-110, 1680, 90, 'text')
    return p


def config(Page):
    p = base(Page, '3 · DATAPATH · CONFIGURACIÓN', 'DATAPATH 1/4 · CONFIGURACIÓN Y CSR',
             'CSR propuestos; sin direcciones asignadas. Perfil seleccionado de una tabla constante.\nLas dimensiones deben coincidir con WIDTH/HEIGHT del generador elaborado; no se cambia su tamaño por software.')
    p.node('cpu', 'RISC-V / LiteX\nEscritura CSR\nprofile_id[8], VC[2]', 60, 270, 370, 140, 'external')
    p.node('shadow', 'R_SHADOW [10] · CSR\n{profile_id, VC}\nLD = cfg_write & stopped\nReset → 0', 560, 250, 400, 180, 'register')
    p.node('validate', 'C_CFG · VALIDACIÓN\nID < N_PROFILES; fuente compatible\nWC ≤ 65535; WC+6 ≤ 2×BUFFER_WORDS\nPaquete par; calendario certificado\nDestino simulación / PHY compatible', 1120, 230, 600, 240, 'operator')
    p.edge('cpu', 'shadow', '[10]', ports='rl')
    p.edge('shadow', 'validate', '[10]', ports='rl')
    p.node('commands', 'ÓRDENES CSR → UC\nAPPLY; START; STOP\npanel_initialized; reset coordinado\nEscribir configuración invalida config_ok\nEscritura activa: rechazar sin alterar Q', 60, 620, 370, 250, 'external')
    p.node('active', 'R_ACTIVE [10]\nD = R_SHADOW\nLD = START_ACCEPT\nReset → 0', 560, 650, 400, 180, 'register')
    p.node('meta', 'ROM_META · CONSTANTES\nDirección: active_profile_id[8]\nWIDTH[16], HEIGHT[16], N_EVENTS[16]\nT_FRAME[32], certificado / destino\nLectura combinacional', 1120, 620, 600, 240, 'memory')
    p.edge('shadow', 'active', '[10]', ports='bt')
    p.edge('active', 'meta', 'ID [8]', ports='rl')
    p.node('wcalc', 'A_WC · SUMA [18]\nW_EXT + (W_EXT << 1)\nExtender WIDTH antes de sumar\nSolo truncar tras validar', 560, 1080, 400, 190, 'operator')
    p.node('descriptor', 'DESCRIPTOR RGB888\ncmd_vc = R_ACTIVE.VC [2]\ncmd_dt = 0x3E [6]\ncmd_wc = WC_EXT[15:0] [16]\n→ Preparador largo, pág. 5', 1120, 1060, 600, 220, 'external')
    p.edge('meta', 'wcalc', 'WIDTH [16]', [(1420, 950), (760, 950)], 'bt')
    p.edge('wcalc', 'descriptor', 'WC [16]', ports='rl')
    p.node('net', 'REDES DE CONFIGURACIÓN ACTIVA\nHEIGHT[16] → contador de líneas\nN_EVENTS[16] → límite de índice\nT_FRAME[32] → límite de cuadro\nactive_profile_id[8] → ROM_EVENT\nVC[2] → descriptor RGB', 60, 1040, 370, 330, 'text')
    p.node('read', 'LECTURA CSR POR CPU\nEstado y diagnóstico\nPerfil / dimensiones activas\nframe_count y primera causa', 60, 1580, 370, 190, 'external')
    p.node('mux', 'M_STATUS · N:1 [32]\nEntradas numeradas:\n0: estado; 1: frame_count\n2: causa; 3: perfil activo\n4: WIDTH; 5: HEIGHT\nResto: 0', 560, 1510, 400, 300, 'mux')
    p.node('status', 'BUS DE ESTADO\nUC: config_ok, running, stopped\nR_FRAMES[32], R_ERROR[5]\nR_ACTIVE y ROM_META\nCada entrada extendida a 32 bits', 1120, 1550, 600, 220, 'external')
    p.edge('status', 'mux', '[32 × N]', ports='lr')
    p.edge('mux', 'read', '[32]', ports='lr')
    p.node('uc', 'FRONTERA UC ↔ DATAPATH\nUC recibe: cfg_match, órdenes CSR, panel_initialized, disponibilidad PHY y condiciones de las otras vistas.\nUC genera: START_ACCEPT, config_ok, running, stopped, comandos de fuente/paquete y enables.\nAPPLY solo valida R_SHADOW. START_ACCEPT captura R_ACTIVE una vez por ejecución; repetir cuadros no lo recarga.\nCPU no alimenta bytes RGB. Para esta propuesta, CSR y vídeo comparten clk; otros dominios requieren un puente CDC.',
           60, 1950, 1660, 270, 'control')
    p.edge('uc', 'active', 'START_ACCEPT [1]', [(890, 1910), (500, 1910), (500, 740)], 'tl', True)
    return p


def calendar(Page):
    p = base(Page, '4 · DATAPATH · CALENDARIO', 'DATAPATH 2/4 · TIEMPO E ÍNDICE DE EVENTOS',
             'ROM_EVENT: calendario expandido de un cuadro. WAIT=0, RGB=1, END=2; 3 es inválido.\nRegistro de evento estable durante su ejecución; no se programa esta ROM por CSR.', 2800)
    # Dos contadores: cada registro tiene MUX de inicialización e incremento explícito.
    for i, (key, width, y, init, step, desc) in enumerate([
        ('TICK', 32, 270, 'FRAME_BEGIN', 'TICK_EN', 'Ciclos desde FRAME_BEGIN'),
        ('IP', 16, 930, 'FRAME_BEGIN', 'EVENT_ADVANCE', 'Índice 0 … N_EVENTS−1'),
    ]):
        p.node(f'zero-{key}', f'0 [{width}]', 60, y+10, 220, 90, 'external')
        p.node(f'add-{key}', f'A{i} · +1 [{width}]\nEntrada: {key}', 360, y+210, 290, 120, 'operator')
        p.node(f'mux-{key}', f'M{i} · 2:1 [{width}]\n0: constante 0\n1: A{i}\nSEL = !{init}', 770, y, 330, 180, 'mux')
        p.node(f'reg-{key}', f'R_{key} [{width}]\nD = M{i}; rst → 0\nLD = {init} | {step}', 1250, y+10, 460, 160, 'register')
        p.edge(f'zero-{key}', f'mux-{key}', f'0 [{width}]', [(310,y+55),(310,y-30),(740,y-30),(740,y+45)], 'ru')
        p.edge(f'add-{key}', f'mux-{key}', f'1 [{width}]', [(710,y+270),(710,y+135)], 'rd')
        p.edge(f'mux-{key}', f'reg-{key}', f'D [{width}]', ports='rl')
        p.edge(f'reg-{key}', f'add-{key}', f'Q [{width}]', [(1480,y+370),(505,y+370)], 'bb')
        p.node(f'ctrl-{key}', f'{init}; {step}; SEL_M{i}\n{desc}', 60, y+430, 1640, 110, 'control')
        p.edge(f'ctrl-{key}', f'mux-{key}', 'SEL [1]', [(880,y+400),(1180,y+400),(1180,y+220),(935,y+220)], 'tb', True)
    p.node('rom', 'ROM_EVENT [N_PROFILES × E_MAX × 66]\nDirección: {active_profile_id[8], IP[16]}\nSalida: KIND[2], RELEASE[32], DEADLINE[32]\nFuera de rango: código inválido\nLectura combinacional', 60, 1600, 650, 240, 'memory')
    p.node('evt', 'R_EVT [66]\nD = ROM_EVENT\nLD = EVENT_LOAD\nReset → 0\nUC conserva event_valid', 850, 1620, 400, 200, 'register')
    p.node('bounds', 'C_IP / C_KIND\nIP < N_EVENTS\nAvance: IP+1 [17]\n< N_EVENTS\nKIND ≠ 3\n→ UC: event_legal', 1400, 1590, 330, 260, 'operator')
    p.edge('reg-IP', 'rom', 'IP [16]', [(1750,1020),(1750,1530),(385,1530)], 'rt')
    p.edge('rom', 'evt', '[66]', ports='rl')
    p.edge('evt', 'bounds', 'KIND [2]', ports='rl')
    p.node('time', 'C_TIME · COMPARACIONES [32]\nreleased = TICK ≥ R_EVT.RELEASE\nlate = TICK > R_EVT.DEADLINE\nframe_late = TICK > T_FRAME\noverflow = TICK == 0xFFFFFFFF', 60, 2020, 650, 240, 'operator')
    p.node('conditions', 'CONDICIONES → UC\nevent_legal; kind[2]; released; late\nframe_late; overflow\nWAIT termina al alcanzar RELEASE\nRGB solo inicia desde RELEASE\nEND requiere cuadro y enlace completos', 850, 2020, 880, 240, 'external')
    p.edge('evt', 'time', 'RELEASE / DEADLINE [32 c/u]', [(1050,1910),(385,1910)], 'bt')
    p.edge('time', 'conditions', '[1 c/u]', ports='rl')
    p.node('policy', 'LÍMITES DE AVANCE\nTICK_EN = frame_active & !overflow; se satura antes de envolver. El tiempo avanza también bajo backpressure.\nEVENT_ADVANCE solo al terminar WAIT o RGB. Antes de IP+1, comprobar IP+1 < N_EVENTS; END no incrementa IP.\nLa tabla debe incluir carga de R_EVT y ciclos de control. END cumple RELEASE ≤ TICK ≤ DEADLINE ≤ T_FRAME.\nFuentes combinacionales se estabilizan antes de EVENT_LOAD; no se presupone la latencia de una BRAM síncrona.',
           60, 2380, 1660, 260, 'text')
    return p


def payload(Page):
    p = base(Page, '5 · DATAPATH · PAYLOAD', 'DATAPATH 3/4 · BYTES, LÍNEAS Y CADENA DSI',
             'Los bloques DSI existentes son externos al planificador. No duplicar su RAM, ECC, CRC ni serializadores.\nEl planificador cuenta bytes aceptados por el preparador; el fin físico se supervisa en la siguiente página.', 2850)
    p.node('source', 'dsi_test_pattern · EXISTENTE\nbyte[8], valid, line_last, frame_last\nstart_valid / start_ready\nframe_done → pág. 6', 60, 260, 480, 180, 'external')
    p.node('gate', 'G_PAYLOAD · COMBINACIONAL\npayload_data = source.byte [8]\npayload_valid = source.valid & G\nsource.ready = payload_ready & G\nG: RGB admitido, sin reset / fallo', 650, 240, 480, 220, 'operator')
    p.node('long', 'dsi_long_packet_tx · EXISTENTE\ncmd_vc[2], cmd_dt[6], cmd_wc[16]\ncmd_valid / cmd_ready\npayload_data / valid / ready\npacket_done → pág. 6', 1250, 240, 480, 220, 'external')
    p.edge('source', 'gate', '[8] + valid', ports='rl')
    p.edge('gate', 'long', '[8] + valid', ports='rl')
    p.node('fire', 'BF = payload_valid & payload_ready\nDF = cmd_valid & cmd_ready\nHandshakes combinacionales [1 c/u]\nready vuelve hacia la fuente', 60, 590, 480, 180, 'operator')
    p.node('packer', 'dsi_lane_packer · EXISTENTE\nBytes [8] → palabras [16]\nkeep[2], valid, last, ready', 650, 590, 480, 180, 'external')
    p.node('transport', 'dsi_hs_transport · EXISTENTE\nBuffer de paquete completo\nHS req / grant / done / complete\nerror / busy → pág. 6', 1250, 590, 480, 180, 'external')
    p.edge('long', 'packer', '[8]', [(1750,350),(1750,530),(890,530)], 'rt')
    p.edge('packer', 'transport', '[16] + keep[2]', ports='rl')
    p.node('phy', 'Árbitro → dphy_hs_tx → dphy_gowin_tx → pads\nBloques externos: petición HS y tiempos eléctricos propios. PROFILE_OK sigue bloqueado para hardware no caracterizado.', 60, 870, 1670, 130, 'external')
    p.edge('transport', 'phy', 'HS', [(1490,820),(895,820)], 'bt')
    for i, (reg, width, y, init, step, limit) in enumerate([
        ('BCNT',16,1120,'DF','BF','WC'),
        ('LINE',16,1780,'FRAME_BEGIN','RGB_COMPLETE','HEIGHT'),
    ]):
        p.node(f'zero-{reg}', f'0 [{width}]', 60,y,230,90,'external')
        p.node(f'add-{reg}', f'A{i+2} · +1 [{width}]\nEntrada: {reg}',340,y+180,300,120,'operator')
        p.node(f'mux-{reg}', f'M{i+2} · 2:1 [{width}]\n0: 0; 1: A{i+2}\nSEL = !{init}',760,y,340,180,'mux')
        p.node(f'reg-{reg}', f'R_{reg} [{width}]\nLD = {init} | {step}\nrst → 0; D = M{i+2}',1250,y,480,180,'register')
        p.edge(f'zero-{reg}',f'mux-{reg}',f'0 [{width}]',[(305,y+45),(305,y-30),(730,y-30),(730,y+45)],'ru')
        p.edge(f'add-{reg}',f'mux-{reg}',f'1 [{width}]',[(700,y+240),(700,y+135)],'rd')
        p.edge(f'mux-{reg}',f'reg-{reg}',f'D [{width}]',ports='rl')
        p.edge(f'reg-{reg}',f'add-{reg}',f'Q [{width}]',[(1490,y+350),(490,y+350)],'bb')
        p.node(f'cmp-{reg}',f'C_{reg} · == {limit} / < {limit}\n{reg} nunca avanza por encima de {limit}\nCondiciones → UC y comprobador de marcas',60,y+420,1670,140,'operator')
    p.node('marks','C_MARK · COMPROBAR SOLO CON BF\nexpect_line_last = (BCNT == WC−1)\nexpect_frame_last = expect_line_last & (LINE == HEIGHT−1)\nmark_error = BF & ((source.line_last ≠ expect_line_last) | (source.frame_last ≠ expect_frame_last))\ncount_error: BF con BCNT ≥ WC, o packet_done sin BCNT == WC. LINE avanza tras RGB_COMPLETE, no tras BF.',60,2460,1670,240,'operator')
    return p


def events(Page):
    p = base(Page, '6 · DATAPATH · EVENTOS Y ESTADO', 'DATAPATH 4/4 · EVENTOS RETENIDOS Y SUPERVISIÓN',
             'No exigir coincidencia de pulsos. pkt_done, hs_done y hs_complete se retienen por paquete.\nframe_done se retiene por cuadro; STOP por ejecución; primera causa de fallo hasta reset.', 2700)
    rows = [
        ('PKT',3,260,'{hs_complete, hs_done, packet_done}','DF','R_PKT_SEEN | events','seen_next == 3’b111 & !transport.busy'),
        ('FRAME',1,740,'source.frame_done','FRAME_BEGIN','R_FRAME_SEEN | source.frame_done','LINE == HEIGHT & frame_seen_next'),
        ('STOP',1,1220,'CSR_STOP','START_ACCEPT','R_STOP | CSR_STOP','STOP_PENDING → UC al fin del cuadro'),
    ]
    for i,(name,width,y,inp,clear,expr,out) in enumerate(rows):
        p.node(f'in-{name}',f'ENTRADA [{width}]\n{inp}',60,y,300,150,'external')
        p.node(f'clear-{name}',f'M{i+4} · 2:1 [{width}]\n0: Q; 1: 0\nSEL = CLR',450,y-10,300,170,'mux')
        p.node(f'or-{name}',f'G{i} · OR [{width}]\nM{i+4} | entrada',850,y-10,350,170,'operator')
        p.node(f'reg-{name}',(f'R_{name}_SEEN [{width}]' if name!='STOP' else 'R_STOP [1]')+'\nLD = ventana | CLR\nrst → 0',1350,y,380,150,'register')
        p.edge(f'in-{name}',f'or-{name}',f'[{width}]',[(390,y+75),(390,y-50),(1025,y-50)],'rt')
        p.edge(f'clear-{name}',f'or-{name}',f'[{width}]',ports='rl')
        p.edge(f'or-{name}',f'reg-{name}',f'D [{width}]',ports='rl')
        p.edge(f'reg-{name}',f'clear-{name}',f'Q [{width}]',[(1540,y+240),(420,y+240),(420,y+32.5)],'bu')
        p.node(f'policy-{name}',f'CLR = {clear}; LD = ventana | CLR\nD = (CLR ? 0 : Q) | entrada; set domina clear; rst → 0\n{out}',60,y+300,1670,110,'control')
    p.node('cause','P_ERR · PRIORIDAD COMBINACIONAL\n1: PHY / aborto; 2: transporte\n3: overflow; 4: plazo; 5: evento ilegal\n6: contador; 7: marcas; 8: fuente\nFAULT_REQ; CAUSE[4]',60,1770,490,240,'operator')
    p.node('err','R_ERROR [5]\n{valid[1], cause[4]}\nLD = FAULT_REQ & !valid\nD = {1, CAUSE}\nrst → 0; primera causa retenida',660,1790,480,210,'register')
    p.node('frame-add','A4 · +1 [32]\nEntrada: R_FRAMES',1250,1720,480,100,'operator')
    p.node('frames','R_FRAMES [32]\nD=A4; LD=FRAME_COMPLETE\nrst → 0; módulo 2³²\n→ CSR frame_count',1250,1870,480,160,'register')
    p.edge('frame-add','frames','D [32]')
    p.edge('frames','frame-add','Q [32]',[(1760,1950),(1760,1685),(1490,1685)],'rt')
    p.edge('cause','err','[5]',ports='rl')
    p.node('uc','FRONTERA CON UC · FSM EN PÁGINAS 7–8\nEntradas: released, late, event_legal, BCNT/WC, LINE/HEIGHT, seen_next, FAULT_REQ y autorización.\nSalidas: START_ACCEPT, FRAME_BEGIN, EVENT_LOAD/ADVANCE, G, cmd_valid, RGB_COMPLETE, FRAME_COMPLETE.\nRGB_COMPLETE: UC emite una vez al comprobar paquete+HS completos y BCNT==WC sin fallo.\nFRAME_COMPLETE: END liberado, todas las líneas+fuente completas, enlace libre y sin fallo. Emitir una vez.\nSTOP conserva el nivel hasta terminar cuadro. Ante fallo, bloquear nuevos paquetes y exigir reset coordinado.\nUn fallo del planificador no conmuta directamente pads ni borra el diagnóstico del wrapper Gowin.',60,2180,1670,350,'control')
    return p


def pages(Page):
    return [('datapath_config', config(Page)), ('datapath_calendario', calendar(Page)),
            ('datapath_payload', payload(Page)), ('datapath_estado', events(Page))]
