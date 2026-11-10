"""Verificación de la FSM documental, sin RTL ni dependencias externas."""
from itertools import product
from pathlib import Path
import xml.etree.ElementTree as E
from verificar_datapath import advance, check_diagram, check_frames, check_reset

IDLE, STREAM = 0, 1


def controls(state, rst, start, ready, is_b, x_end, y_end):
    start_ready = not rst and state == IDLE
    valid = not rst and state == STREAM
    fire = valid and ready
    return (start_ready and start,
            fire and not is_b,
            fire and is_b and not x_end,
            fire and is_b and x_end and not y_end,
            fire and is_b and x_end and y_end,
            start_ready, valid, state == STREAM)


def uc_edge(state, done, rst, start, ready, is_b, x_end, y_end):
    init, _, _, _, finish, *_ = controls(state, rst, start, ready, is_b, x_end, y_end)
    if rst:
        return IDLE, False
    if state == IDLE:
        return (STREAM if init else IDLE), False
    return (IDLE if finish else STREAM), finish


def check_matrix():
    covered = set()
    cases = 0
    for state, rst, start, ready, is_b, x_end, y_end, done in product((0, 1), repeat=8):
        c = controls(state, rst, start, ready, is_b, x_end, y_end)
        after = uc_edge(state, done, rst, start, ready, is_b, x_end, y_end)
        expected = [False]*5
        next_state = state
        # Oráculo: filas priorizadas de la tabla, independiente de las ecuaciones.
        if rst:
            row, next_state = 'reset', IDLE
        elif state == IDLE:
            row = 'start' if start else 'idle'
            if start:
                expected[0], next_state = True, STREAM
        elif not ready:
            row = 'pause'
        elif not is_b:
            row, expected[1] = 'component', True
        elif not x_end:
            row, expected[2] = 'pixel', True
        elif not y_end:
            row, expected[3] = 'line', True
        else:
            row, expected[4], next_state = 'finish', True, IDLE
        covered.add(row)
        assert c[:5] == tuple(expected)
        assert sum(c[:5]) <= 1
        assert not (c[5] and c[6])
        assert c[7] == (state == STREAM)
        assert after == (next_state, expected[4])
        assert c[5] == (not rst and state == IDLE)
        assert c[6] == (not rst and state == STREAM)
        cases += 1
    assert covered == {'reset', 'start', 'idle', 'pause', 'component', 'pixel', 'line', 'finish'}
    print(f'PASS matriz UC: {cases} casos; todas las filas, reset, controles y R_DONE')


def advance_fsm(state, width, height, start, ready, rst=False):
    x, y, comp, active, done = state
    code = STREAM if active else IDLE
    init, step_c, step_x, step_y, *_ = controls(
        code, rst, start, ready, comp == 2, x == width-1, y == height-1)
    next_state, next_done = uc_edge(code, done, rst, start, ready,
                                    comp == 2, x == width-1, y == height-1)
    if rst:
        x, y, comp = 0, 0, 0
    else:
        if init or step_x or step_y:
            x = x+1 if step_x else 0
        if init or step_y:
            y = y+1 if step_y else 0
        if init or step_c or step_x or step_y:
            comp = comp+1 if step_c else 0
    return x, y, comp, next_state == STREAM, next_done


def check_equivalence():
    cases = 0
    for w, h in ((8, 1), (16, 2), (720, 720)):
        for x, y, c, active, done, start, ready, rst in product(
                (0, w-1), sorted({0, h-1}), range(3), (False, True),
                (False, True), (False, True), (False, True), (False, True)):
            state = (x, y, c, active, done)
            assert advance_fsm(state, w, h, start, ready, rst) == advance(
                state, w, h, start, ready, rst)
            cases += 1
    print(f'PASS equivalencia UC/datapath: {cases} combinaciones de posiciones y entradas')


def check_fsm_page():
    r = E.parse(Path(__file__).with_name('DSI_TEST_PATTERN.drawio')).getroot()
    page = r.find("diagram[@id='fsm-control']")
    assert page is not None
    cells = page.findall('.//mxCell')
    labels = {c.get('id'): c.get('value', '') for c in cells}
    assert labels['idle'].startswith('IDLE · 0')
    assert labels['stream'].startswith('STREAM · 1')
    arcs = [(c.get('source'), c.get('target')) for c in cells if c.get('edge') == '1']
    for arc in (('idle','idle'), ('idle','stream'), ('stream','stream'), ('stream','idle')):
        assert arcs.count(arc) == 1
    assert 'R_DONE [1]' in labels['done-reg']
    print('PASS diagrama FSM: dos estados, cuatro arcos y registro R_DONE')


if __name__ == '__main__':
    check_diagram()
    check_fsm_page()
    check_matrix()
    check_equivalence()
    for w, h in ((8, 1), (16, 2), (720, 720)):
        check_frames(w, h, advance_fn=advance_fsm)
    check_reset(advance_fn=advance_fsm)
    print('FSM documental verificada; sin simulación ni síntesis RTL.')
