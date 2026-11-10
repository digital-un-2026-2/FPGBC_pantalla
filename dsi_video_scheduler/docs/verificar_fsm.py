"""Verifica la especificación simbólica de la FSM; no sustituye simulación RTL."""
from itertools import product
from generar_fsm import CODE, EVENT_STATES, FRAME_STATES, transition


def check():
    assert len(CODE) == len(set(CODE.values())) == 10
    assert set(CODE.values()) == set(range(10))
    keys = ('rst', 'hard_fault', 'local_fault', 'error_valid', 'source_ready',
            'cmd_ready', 'released', 'pkt_ok', 'frame_ok', 'stop_next')
    count = 0
    for state, kind, bits in product([*CODE, *range(10,16)], range(4), product((False, True), repeat=len(keys))):
        flags = dict(zip(keys, bits))
        flags.update(kind=kind, start_accept=True, ip_ok=True,
                     next_ip_ok=True, last_bf=True)
        nxt, out = transition(state, **flags)
        assert nxt in CODE
        if flags['rst']:
            assert nxt == 'IDLE' and not any(out.values())
        elif state not in CODE:
            assert nxt == 'FAULT' and not out['G'] and not out['cmd_valid']
        elif state == 'FAULT':
            assert nxt == 'FAULT' and not out['running']
        elif state != 'IDLE' and any(flags[k] for k in ('hard_fault','local_fault','error_valid')):
            assert nxt == 'FAULT'
            assert not any(out[k] for k in ('FRAME_BEGIN','EVENT_LOAD','EVENT_ADVANCE','RGB_COMPLETE','FRAME_COMPLETE'))
        if not flags['rst']:
            assert out['frame_active'] == (state in FRAME_STATES)
            assert out['event_valid'] == (state in EVENT_STATES)
        assert not out['FRAME_COMPLETE'] or (state == 'RELEASE' and nxt == 'FINISH' and kind == 2)
        assert not out['RGB_COMPLETE'] or (state == 'TX_WAIT' and nxt == 'ADVANCE')
        assert not out['EVENT_ADVANCE'] or (state == 'ADVANCE' and nxt == 'LOAD')
        assert not out['FRAME_BEGIN'] or (state == 'ARM' and nxt == 'LOAD')
        if flags['hard_fault'] or flags['rst'] or state not in CODE:
            assert not out['G'] and not out['cmd_valid'] and not out['source_start_valid']
        count += 1

    def expect(state, nxt, action=None, **flags):
        got, controls = transition(state, **flags)
        assert got == nxt, (state, got, nxt)
        if action:
            assert controls[action], (state, action)
        return controls

    # Un recorrido completo, y un segundo cuadro sin volver a aceptar START.
    expect('IDLE','ARM','START_ACCEPT',start_accept=True)
    expect('ARM','ARM',source_ready=False)
    expect('ARM','LOAD','FRAME_BEGIN',source_ready=True)
    expect('LOAD','RELEASE','EVENT_LOAD',ip_ok=True)
    expect('RELEASE','RELEASE',kind=0,released=False)
    expect('RELEASE','ADVANCE',kind=0,released=True)
    expect('ADVANCE','LOAD','EVENT_ADVANCE',next_ip_ok=True)
    expect('LOAD','RELEASE','EVENT_LOAD',ip_ok=True)
    expect('RELEASE','CMD',kind=1,released=True)
    expect('CMD','CMD',cmd_ready=False)
    expect('CMD','PAYLOAD',cmd_ready=True)
    expect('PAYLOAD','PAYLOAD',last_bf=False)
    expect('PAYLOAD','TX_WAIT',last_bf=True)
    expect('TX_WAIT','TX_WAIT',pkt_ok=False)
    expect('TX_WAIT','ADVANCE','RGB_COMPLETE',pkt_ok=True)
    expect('ADVANCE','LOAD','EVENT_ADVANCE',next_ip_ok=True)
    expect('RELEASE','RELEASE',kind=2,released=True,frame_ok=False)
    expect('RELEASE','FINISH','FRAME_COMPLETE',kind=2,released=True,frame_ok=True)
    expect('FINISH','ARM',stop_next=False)
    expect('FINISH','IDLE',stop_next=True)
    expect('PAYLOAD','PAYLOAD',stop_next=True,last_bf=False)
    expect('CMD','CMD',stop_next=True,cmd_ready=False)
    for state in ('LOAD','ADVANCE'):
        expect(state,'FAULT','LD_ERROR',ip_ok=False,next_ip_ok=False)
    expect('RELEASE','FAULT','LD_ERROR',kind=3)
    expect('PAYLOAD','PAYLOAD',last_bf=True,bcnt_lt_wc=False)
    # Un error del byte aceptado no cancela su G combinacional; un fallo urgente sí.
    assert expect('PAYLOAD','FAULT',local_fault=True)['G']
    assert not expect('PAYLOAD','FAULT',hard_fault=True)['G']
    # El plazo usa >; igualdad permite el éxito. Evento anterior no vive en ADVANCE.
    for tick in (99, 100, 101):
        expect('TX_WAIT','FAULT' if tick>100 else 'ADVANCE',pkt_ok=True,hard_fault=tick>100)
    assert 'ADVANCE' not in EVENT_STATES and 'FINISH' not in FRAME_STATES
    # La agregación de fines permite cualquier orden y conserva clear+set.
    for sequence in ((1,2,4),(4,1,2),(2,4,1),(7,)):
        seen=0
        for incoming in sequence:
            seen |= incoming
        assert seen == 7
    assert (0 | 4) == 4  # DF limpia y hs_complete en ese ciclo se conserva.
    print(f'PASS: {count} combinaciones simbólicas y recorridos de guards/acciones.')
    print('Límite: modelo de especificación; no es simulación RTL ni validación física.')


if __name__ == '__main__':
    check()
