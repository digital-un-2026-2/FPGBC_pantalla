"""Verificación de especificación UC_SUP; no es simulación RTL/física."""
from itertools import product
from pathlib import Path
import xml.etree.ElementTree as ET

RESET, WAIT, RELEASE, READY, ACTIVE, BLOCKED = 0b000, 0b001, 0b011, 0b010, 0b110, 0b111
LEGAL = {RESET, WAIT, RELEASE, READY, ACTIVE, BLOCKED}


def step(state, started, *, rst=0, profile=1, lock=1, abort=0, event=0, ready=0):
    boot = profile and lock and not abort and not event
    fault = event or (started and (not lock or abort or not profile)) or (state == ACTIVE and not ready)
    fire = not rst and state == WAIT and boot and not fault
    if rst:
        return RESET, 0
    if state not in LEGAL or fault:
        return BLOCKED, started
    nxt = {
        RESET: WAIT,
        WAIT: RELEASE if boot else WAIT,
        RELEASE: READY,
        READY: ACTIVE if ready else READY,
        ACTIVE: ACTIVE,
        BLOCKED: BLOCKED,
    }[state]
    return nxt, bool(started or fire)


def release_gate(state, *, rst=0, profile=1, lock_sync=1, lock_raw=1, abort_raw=0, event_raw=0):
    return state == RELEASE and not rst and profile and lock_sync and lock_raw and not abort_raw and not event_raw


def capture_flags(started, abort_seen, clock_fault, *, rst=0, abort_raw=0, lock_raw=1):
    if rst:
        return 0, 0
    return bool(abort_seen or (started and abort_raw)), bool(clock_fault or (started and not lock_raw))


def main():
    rows = 0
    for state in range(8):
        for rst, profile, lock, abort, event, started, ready in product((0, 1), repeat=7):
            ns, armed = step(state, started, rst=rst, profile=profile, lock=lock, abort=abort, event=event, ready=ready)
            assert ns in LEGAL
            if rst:
                assert (ns, armed) == (RESET, 0)
            elif state not in LEGAL:
                assert ns == BLOCKED
            elif event or (started and (not lock or abort or not profile)) or (state == ACTIVE and not ready):
                assert ns == BLOCKED
            elif state == BLOCKED:
                assert ns == BLOCKED
            if started and not rst:
                assert armed
            rows += 1
    assert rows == 1024

    # Recorrido normal, sin segundo permiso de arranque ni contador de llenado.
    s, armed = RESET, 0
    for expected, ready in [(WAIT, 0), (RELEASE, 0), (READY, 0), (READY, 0), (ACTIVE, 1), (ACTIVE, 1)]:
        s, armed = step(s, armed, ready=ready)
        assert s == expected
    assert armed
    for a, b in zip((RESET, WAIT, RELEASE, READY), (WAIT, RELEASE, READY, ACTIVE)):
        assert (a ^ b).bit_count() == 1
    for conditions in [dict(lock=0), dict(abort=1), dict(profile=0)]:
        assert step(WAIT, 0, **conditions) == (WAIT, 0)
    assert step(ACTIVE, 1, ready=0)[0] == BLOCKED

    # Pulso de aborto entre flancos durante RELEASE: el nivel desaparece antes
    # de EV_REF, pero la memoria raw impide una segunda limpieza de INHIBIT.
    abort_seen, clock_fault = capture_flags(1, 0, 0, abort_raw=1)
    assert (abort_seen, clock_fault) == (1, 0)
    abort_seen, clock_fault = capture_flags(1, abort_seen, clock_fault, abort_raw=0)
    event_raw = abort_seen or clock_fault
    assert not release_gate(RELEASE, event_raw=event_raw)
    s, armed, ev0, ev1 = RELEASE, 1, 0, 0
    for expected in (READY, READY, BLOCKED):
        s, armed = step(s, armed, event=ev1)
        ev0, ev1 = event_raw, ev0
        assert s == expected
    assert step(BLOCKED, 1, ready=1) == (BLOCKED, 1)
    assert step(BLOCKED, 1, rst=1) == (RESET, 0)

    # Pérdida breve de PLL, eventos simultáneos y ausencia de falsa causa inicial.
    assert capture_flags(0, 0, 0, abort_raw=1, lock_raw=0) == (0, 0)
    assert capture_flags(1, 0, 0, lock_raw=0) == (0, 1)
    assert capture_flags(1, 0, 1, lock_raw=1) == (0, 1)
    assert capture_flags(1, 0, 0, abort_raw=1, lock_raw=0) == (1, 1)
    assert capture_flags(1, 1, 1, rst=1, abort_raw=1, lock_raw=0) == (0, 0)
    for state in range(8):
        for raw in product((0, 1), repeat=6):
            rst, profile, ls, lr, ar, er = raw
            out = release_gate(state, rst=rst, profile=profile, lock_sync=ls, lock_raw=lr, abort_raw=ar, event_raw=er)
            if rst or not profile or not ls or not lr or ar or er or state != RELEASE:
                assert not out

    root = ET.parse(Path(__file__).with_name('DPHY_GOWIN_TX.drawio')).getroot()
    pages = {d.get('id'): d for d in root.findall('diagram')}
    graph = pages['fsm-supervisor']
    names = {'reset': ('RESET', RESET), 'wait': ('WAIT_LOCK', WAIT), 'release': ('RELEASE', RELEASE),
             'ready': ('WAIT_READY', READY), 'active': ('ACTIVE', ACTIVE), 'blocked': ('BLOCKED', BLOCKED)}
    for ident, (name, code) in names.items():
        node = graph.find(f"mxGraphModel/root/mxCell[@id='{ident}']")
        assert node is not None and node.get('value').startswith(f'{name} · {code:03b}')
    print('PASS UC_SUP: 1024 filas; recorrido Gray; espera/READY; códigos inválidos; prioridades; eventos breves; 512 máscaras RELEASE; estados del Draw.io.')


if __name__ == '__main__':
    main()
