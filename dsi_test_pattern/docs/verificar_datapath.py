"""Comprueba el diseño documental; no es un testbench de RTL."""
from pathlib import Path
import xml.etree.ElementTree as E


def outputs(state, width, height, rst=False):
    x, y, c, active, done = state
    valid = active and not rst
    thresholds = [x >= i*(width//8) for i in range(1, 8)]
    band = max([0] + [i for i, t in enumerate(thresholds, 1) if t])
    rgb = (0xFFFFFF, 0xFFFF00, 0x00FFFF, 0x00FF00,
           0xFF00FF, 0xFF0000, 0x0000FF, 0x000000)[band]
    data = ((rgb >> (16-8*c)) & 255) if valid else 0
    line = valid and c == 2 and x == width-1
    frame = line and y == height-1
    return data, valid, line, frame, not rst and not active, done


def advance(state, width, height, start, ready, rst=False):
    x, y, c, active, _ = state
    if rst:
        return 0, 0, 0, False, False
    init = start and not active
    fire = active and ready
    is_b, x_end, y_end = c == 2, x == width-1, y == height-1
    comp = fire and not is_b
    pixel = fire and is_b and not x_end
    line = fire and is_b and x_end and not y_end
    finish = fire and is_b and x_end and y_end
    assert sum((init, comp, pixel, line, finish)) <= 1
    # M0/M1/M2 + LD, exactamente como la lámina de recorrido.
    if init or pixel or line:
        x = x+1 if pixel else 0
    if init or line:
        y = y+1 if line else 0
    if init or comp or pixel or line:
        c = c+1 if comp else 0
    return x, y, c, (active or init) and not finish, finish


def check_frames(width, height, advance_fn=advance):
    reference = ((255,255,255), (255,255,0), (0,255,255), (0,255,0),
                 (255,0,255), (255,0,0), (0,0,255), (0,0,0))
    state = (0, 0, 0, False, False)
    accepted = frames = line_count = tick = 0
    total = 3*width*height
    while frames < 2:
        data, valid, line_last, frame_last, start_ready, done = outputs(state, width, height)
        ready = tick % 11 not in (2, 3, 7)
        if start_ready:  # start_valid permanentemente alto; sin CPU.
            assert not valid
            accepted = line_count = 0
        if valid:
            pixel_index, channel = divmod(accepted, 3)
            row, column = divmod(pixel_index, width)
            assert data == reference[(column*8)//width][channel]
            assert line_last == (column == width-1 and channel == 2)
            assert frame_last == (accepted == total-1)
            if ready:
                accepted += 1
                line_count += int(line_last)
        after = advance_fn(state, width, height, True, ready)
        if valid and not ready:
            assert outputs(after, width, height)[:4] == (data, valid, line_last, frame_last)
        if after[4]:
            assert accepted == total and line_count == height
            assert not after[3]
            frames += 1
        if done:
            assert not after[4]
        state = after
        assert 0 <= state[0] < width and 0 <= state[1] < height and state[2] in (0, 1, 2)
        tick += 1
    print(f'PASS modelo {width}x{height}: dos cuadros, RGB, marcas, pausas y reinicio autónomo')


def check_reset(advance_fn=advance):
    for c in range(3):
        for x, y in ((0,0), (7,0), (7,1)):
            state = (x, y, c, True, False)
            assert outputs(state, 8, 2, True)[:5] == (0, False, False, False, False)
            state = advance_fn(state, 8, 2, True, True, True)
            assert state == (0, 0, 0, False, False)
            state = advance_fn(state, 8, 2, True, True)
            assert outputs(state, 8, 2)[:4] == (255, True, False, False)
    print('PASS reset: R/G/B, límites, coincidencia con entrega e inicio posterior')


def check_diagram():
    root = E.parse(Path(__file__).with_name('DSI_TEST_PATTERN.drawio')).getroot()
    assert len(root.findall('diagram')) == int(root.get('pages')) == 4
    for page in root.findall('diagram'):
        cells = page.findall('.//mxCell')
        ids = [c.get('id') for c in cells]
        assert len(ids) == len(set(ids))
        for cell in cells:
            if cell.get('edge') == '1':
                assert cell.get('source') in ids and cell.get('target') in ids
            if 'rhombus;' in cell.get('style', ''):
                edges = [e for e in cells if e.get('source') == cell.get('id')]
                assert len(edges) == 2
                assert {e.get('value').split()[0] for e in edges} == {'Sí', 'No'}
    print('PASS XML: cuatro páginas, IDs únicos por página, conexiones y ramas del flujo')


if __name__ == '__main__':
    check_diagram()
    for w, h in ((8, 1), (16, 2), (720, 720)):
        check_frames(w, h)
    check_reset()
    print('Verificación de ecuaciones y documentación; las pruebas RTL son independientes.')
