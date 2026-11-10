"""Comprobación ejecutable del calendario propuesto; no modela una PHY física."""
from fractions import Fraction as F


def check_profile(prepare_cycles=3):
    period = F(25)
    ui = period / 8
    durations = dict(lpx=2, clk_prepare=2, clk_zero=10, clk_pre=1,
                     hs_prepare=prepare_cycles, hs_zero=5, hs_trail=3,
                     clk_post=9, clk_trail=3, hs_exit=4)
    t = {name: count * period for name, count in durations.items()}
    checks = [t['lpx'] >= 50, 38 <= t['clk_prepare'] <= 95,
              t['clk_prepare'] + t['clk_zero'] >= 300,
              t['clk_pre'] >= 8 * ui,
              40 + 4 * ui <= t['hs_prepare'] <= 85 + 6 * ui,
              t['hs_prepare'] + t['hs_zero'] >= 145 + 10 * ui,
              max(8 * ui, 60 + 4 * ui) <= t['hs_trail'] <= 105 + 12 * ui,
              t['clk_post'] >= 60 + 52 * ui,
              60 <= t['clk_trail'] <= 105 + 12 * ui, t['hs_exit'] >= 100]
    if not all(checks):
        raise ValueError('perfil fuera de los limites de contraste')


def check_schedule(words, missing=None, partial=None):
    pending = active = None
    accepted, transmitted = [], []
    peak = 0
    for cycle in range(words + 2):
        # Termina el intervalo serial anterior, antes de cargar ACTIVE.
        if active is not None:
            transmitted.append(active)
        active, pending = pending, None
        if cycle < words:
            if cycle == missing:
                raise ValueError('underflow')
            if cycle == partial:
                raise ValueError('lane parcial sin politica fisica')
            pending = cycle
            accepted.append(cycle)
        # En C0 sale Sync, nunca el primer payload.
        assert (cycle == 0) == (active is None and cycle < words + 1)
        peak = max(peak, int(active is not None) + int(pending is not None))
        # El arbitro pide parada en CN: la palabra final sigue activa.
        if cycle == words:
            assert active == words - 1
            assert len(transmitted) == words - 1
        if cycle == words + 1:
            assert active is None and pending is None
    assert accepted == transmitted == list(range(words))
    assert peak == min(2, words)


if __name__ == '__main__':
    check_profile()
    lengths = (1, 2, 3, 4, 1083, 2048)
    for length in lengths:
        check_schedule(length)
    negatives = (lambda: check_profile(1), lambda: check_profile(5),
                 lambda: check_schedule(3, missing=1),
                 lambda: check_schedule(3, partial=2))
    for case in negatives:
        try:
            case()
        except ValueError:
            continue
        raise AssertionError('caso negativo aceptado')
    print('PASS: perfil S320; 6 longitudes; 4 rechazos; maximo 2 palabras')
