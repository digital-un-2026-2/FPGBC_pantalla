"""Especificación simbólica y vistas de la FSM propuesta, sin RTL."""

STATES = (
    ('IDLE', '0000', 'stopped = chain_free & !rst & !R_ERROR.valid; habilita CSR',
     'START_ACCEPT → ARM; si no, conservar estado'),
    ('ARM', '0001', 'source.start_valid = !HARD_BLOCK',
     'SF → LOAD; sin ready, conservar estado'),
    ('LOAD', '0010', 'EVENT_LOAD = IP_OK & !FAULT_REQ',
     'IP_OK → RELEASE; si no, FAULT / causa 5'),
    ('RELEASE', '0011', 'Según KIND y released; END puede emitir FRAME_COMPLETE',
     'WAIT → ADVANCE; RGB → CMD; END_OK → FINISH'),
    ('CMD', '0100', 'cmd_valid = !HARD_BLOCK; campos desde R_ACTIVE',
     'DF → PAYLOAD; sin ready, conservar descriptor'),
    ('PAYLOAD', '0101', 'G = !HARD_BLOCK & (BCNT < WC)',
     'LAST_BF → TX_WAIT; sin BF, conservar byte y contadores'),
    ('TX_WAIT', '0110', 'Capturar finales; RGB_COMPLETE = PKT_OK & !FAULT_REQ',
     'PKT_OK → ADVANCE; si no, conservar estado'),
    ('ADVANCE', '0111', 'EVENT_ADVANCE = NEXT_IP_OK & !FAULT_REQ',
     'NEXT_IP_OK → LOAD; si no, FAULT / causa 5'),
    ('FINISH', '1000', 'Cuadro ya contado; frame_active = 0',
     'STOP_NEXT → IDLE; si no, ARM para repetir'),
    ('FAULT', '1001', 'running=0; stopped=0; bloquear nuevos inicios',
     'Conservar estado hasta rst; no hay CLEAR_ERROR parcial'),
)
CODE = {name: int(code, 2) for name, code, _, _ in STATES}
FRAME_STATES = {'LOAD', 'RELEASE', 'CMD', 'PAYLOAD', 'TX_WAIT', 'ADVANCE'}
EVENT_STATES = {'RELEASE', 'CMD', 'PAYLOAD', 'TX_WAIT'}


def transition(state, **f):
    """Modelo de guards/acciones; los flags proceden del datapath, no de E/S reales.

    HARD_BLOCK se calcula sin DF/BF. Un fallo local detectado al consumir un
    byte cambia el estado, pero no cancela retroactivamente ese handshake.
    """
    get = lambda key, default=False: f.get(key, default)
    illegal = state not in CODE
    running = not illegal and state not in ('IDLE', 'FAULT')
    hard = get('rst') or illegal or state == 'FAULT' or get('error_valid') or get('hard_fault')
    fault = illegal or (running and (get('hard_fault') or get('local_fault') or get('error_valid')))
    out = {
        'source_start_valid': state == 'ARM' and not hard,
        'cmd_valid': state == 'CMD' and not hard,
        'G': state == 'PAYLOAD' and get('bcnt_lt_wc', True) and not hard,
        'frame_active': state in FRAME_STATES,
        'event_valid': state in EVENT_STATES,
        'pkt_window': state in ('PAYLOAD', 'TX_WAIT'),
        'running': running,
        'START_ACCEPT': False, 'FRAME_BEGIN': False, 'EVENT_LOAD': False,
        'EVENT_ADVANCE': False, 'RGB_COMPLETE': False, 'FRAME_COMPLETE': False,
        'LD_ERROR': False,
    }
    out['pkt_window'] |= out['cmd_valid'] and get('cmd_ready')
    if get('rst'):
        return 'IDLE', {k: False for k in out}
    if state == 'FAULT':
        return 'FAULT', out
    if fault:
        out['LD_ERROR'] = not get('error_valid')
        return 'FAULT', out
    nxt = state
    if state == 'IDLE' and get('start_accept') and not hard:
        nxt, out['START_ACCEPT'] = 'ARM', True
    elif state == 'ARM' and out['source_start_valid'] and get('source_ready'):
        nxt, out['FRAME_BEGIN'] = 'LOAD', True
    elif state == 'LOAD':
        if get('ip_ok'):
            nxt, out['EVENT_LOAD'] = 'RELEASE', True
        else:
            nxt, out['LD_ERROR'] = 'FAULT', not get('error_valid')
    elif state == 'RELEASE':
        if get('kind', 3) not in (0, 1, 2):
            nxt, out['LD_ERROR'] = 'FAULT', not get('error_valid')
        elif get('released'):
            if get('kind') == 0:
                nxt = 'ADVANCE'
            elif get('kind') == 1:
                nxt = 'CMD'
            elif get('frame_ok'):
                nxt, out['FRAME_COMPLETE'] = 'FINISH', True
    elif state == 'CMD' and out['cmd_valid'] and get('cmd_ready'):
        nxt = 'PAYLOAD'
    elif state == 'PAYLOAD' and out['G'] and get('last_bf'):
        nxt = 'TX_WAIT'
    elif state == 'TX_WAIT' and get('pkt_ok'):
        nxt, out['RGB_COMPLETE'] = 'ADVANCE', True
    elif state == 'ADVANCE':
        if get('next_ip_ok'):
            nxt, out['EVENT_ADVANCE'] = 'LOAD', True
        else:
            nxt, out['LD_ERROR'] = 'FAULT', not get('error_valid')
    elif state == 'FINISH':
        nxt = 'IDLE' if get('stop_next') else 'ARM'
    return nxt, out


def transitions(Page):
    p = Page('7 · FSM · TRANSICIONES', 3000)
    p.node('title', 'FSM · PLANIFICADOR DSI · TRANSICIONES', 60, 20, 1680, 70, 'text')
    p.node('subtitle', 'PROPUESTA · STATE[3:0], diez códigos usados. Registros en ↑clk; rst síncrono activo alto.\nToda transición normal exige !FAULT_REQ. Los controles de handshake son combinacionales antes del flanco.',
           60, 100, 1680, 100, 'text')
    layout = {'IDLE': (430, 260), 'ARM': (430, 520), 'LOAD': (430, 780),
              'RELEASE': (430, 1070), 'CMD': (430, 1410), 'PAYLOAD': (430, 1690),
              'TX_WAIT': (430, 1970), 'ADVANCE': (430, 2250),
              'FINISH': (1230, 1070), 'FAULT': (1230, 2250)}
    brief = {'IDLE': 'Configurar / esperar START', 'ARM': 'Solicitar inicio de fuente',
             'LOAD': 'Cargar evento desde ROM', 'RELEASE': 'Esperar instante y decodificar\nEND aceptado: FRAME_COMPLETE',
             'CMD': 'Ofrecer descriptor RGB', 'PAYLOAD': 'Consumir bytes con handshake',
             'TX_WAIT': 'Esperar finales retenidos', 'ADVANCE': 'Incrementar IP una vez',
             'FINISH': 'Resolver STOP / repetición', 'FAULT': 'Bloqueado hasta reset'}
    for name, code, _, _ in STATES:
        x, y = layout[name]
        p.node(name, f'{name} · {code}\n{brief[name]}', x, y,
               630 if x == 430 else 500, 160, 'state' if name != 'FAULT' else 'fault')
    for a, b, label in [('IDLE','ARM','START_ACCEPT'), ('ARM','LOAD','SF / FRAME_BEGIN'),
                        ('LOAD','RELEASE','IP_OK / EVENT_LOAD'), ('RELEASE','CMD','released & KIND=RGB'),
                        ('CMD','PAYLOAD','DF'), ('PAYLOAD','TX_WAIT','LAST_BF'),
                        ('TX_WAIT','ADVANCE','PKT_OK / RGB_COMPLETE')]:
        p.edge(a,b,label)
    p.edge('RELEASE','ADVANCE','released & KIND=WAIT', [(300,1150),(300,2330)], 'll')
    p.edge('RELEASE','FINISH','END_OK', ports='rl')
    p.edge('ADVANCE','LOAD','NEXT_IP_OK / EVENT_ADVANCE', [(745,2500),(170,2500),(170,860)], 'bl')
    p.edge('FINISH','IDLE','STOP', [(1740,1150),(1780,1150),(1780,220),(745,220)], 'rt')
    p.edge('FINISH','ARM','!STOP_NEXT', [(1480,1010),(1160,1010),(1160,600)], 'tr')
    p.node('reset', 'rst desde cualquier estado → IDLE\nLimpiar registros y autorización\nPrioridad absoluta', 60, 2600, 700, 150, 'terminal')
    p.node('global', 'FALLO GLOBAL → FAULT\nPHY, transporte, plazo, contadores o marcas\nLOAD / ADVANCE sin índice válido → causa 5\nKIND inválido o STATE=10…15 → causa 5\nSolo reset coordinado permite salir', 1130, 1830, 610, 250, 'fault')
    p.edge('global','FAULT','FAULT_REQ', [(1435,2160),(1480,2160)], ports='bt', dashed=True)
    p.node('holds', 'RETENCIÓN Y PRIORIDAD\nSin guard habilitado, conservar STATE. LOAD, ADVANCE y FINISH resuelven en un ciclo sin fallo.\n1. rst; 2. FAULT_REQ; 3. transición normal. FAULT es absorbente; STOP no aborta el cuadro.\nSF = source.start_valid & source.start_ready. DF = cmd_valid & cmd_ready. LAST_BF = BF & (BCNT=WC−1).',
           60, 2790, 1680, 150, 'text')
    p.node('guards', 'GUARDS DEL DATAPATH\n\nPKT_OK: tres finales retenidos,\ntransporte libre y BCNT=WC.\n\nEND_OK: KIND=END, released,\nLINE=HEIGHT, FRAME_SEEN_NEXT,\nfuente y enlace libres, sin paquete\npendiente y END en último índice.\n\nPlazo de evento solo en RELEASE,\nCMD, PAYLOAD y TX_WAIT.\n\nTICK avanza también bajo pausas.\nEn FINISH, STOP = STOP_NEXT.',
           1200, 1300, 530, 480, 'text')
    return p


def controls(Page):
    p = Page('8 · FSM · CONTROLES', 2650)
    p.node('title', 'FSM · CONTROLES Y CONDICIONES DE SALIDA', 60, 20, 1680, 70, 'text')
    p.node('subtitle', 'Todos los pulsos son enables presentes antes del flanco que ejecuta la operación; no registros ACTION.\nSeñales no indicadas = 0. La captura de eventos y los contadores siguen las ecuaciones del datapath.',
           60, 100, 1680, 100, 'text')
    p.node('headers', 'ESTADO [4]                         CONTROLES ACTIVOS / ENTRADAS AL DATAPATH', 60, 205, 1680, 60, 'text')
    for i, (name, code, action, guard) in enumerate(STATES):
        y = 300+i*175
        p.node(f's-{name}', f'{name}\n{code}', 60, y, 300, 145, 'register')
        p.node(f'a-{name}', action, 420, y, 760, 145, 'register')
        p.node(f'g-{name}', guard, 1240, y, 500, 145, 'external')
    p.node('masks', 'MÁSCARAS Y VENTANAS\nHARD_BLOCK = rst | estado ilegal | STATE=FAULT | R_ERROR.valid | fallo urgente sin depender de DF/BF.\ncmd_valid y G usan HARD_BLOCK; mark_error / count_error derivados de BF no vuelven a enmascarar ese mismo BF.\nframe_active: LOAD / RELEASE / CMD / PAYLOAD / TX_WAIT / ADVANCE.\npkt_window: DF o PAYLOAD / TX_WAIT; frame_window: FRAME_BEGIN o frame_active.\nSTOP se captura mientras running o START_ACCEPT. running: todos excepto IDLE / FAULT. stopped: IDLE & chain_free.',
           60, 2110, 1680, 260, 'control')
    p.node('memory', 'MEMORIA UC: STATE[4] + config_ok[1] + panel_initialized[1] = 6 bits. Ventanas y flags de actividad se decodifican de STATE.\nTotal propuesto: datapath 198 + CSR R_SHADOW 10 + UC 6 = 214 bits, sin ROM ni módulos externos.\nComandos detenidos: cfg_write > APPLY > escritura de autorización > START. STOP puede coincidir con START.\nDiseño documentado, no RTL implementado. Verificación simbólica: verificar_fsm.py; límites y ecuaciones: fsm.md.',
           60, 2420, 1680, 180, 'text')
    return p


def pages(Page):
    return [('fsm', transitions(Page)), ('fsm_controles', controls(Page))]
