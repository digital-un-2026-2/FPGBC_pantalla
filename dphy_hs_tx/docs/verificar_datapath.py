"""Comprobaciones del diseño documental, sin simular RTL ni primitivas."""
from verificar_contrato import check_profile, check_schedule


def expiration(length):
    remaining = length - 1
    for boundary in range(1, length + 1):
        # La UC observa el valor anterior al flanco.
        expired = remaining == 0
        assert expired == (boundary == length)
        if expired:
            return boundary
        remaining -= 1
    raise AssertionError('temporizador no termina')


def pipeline(length):
    source = [((i * 971 + 0x8031) & 0xffff, i == length - 1)
              for i in range(length)]
    pending = active = None
    result = []
    retained_data = None
    for edge in range(length + 2):
        if active is not None:
            result.append(active)
        active = pending
        if active is not None:
            retained_data = active[0]
        pending = source[edge] if edge < length else None
        assert int(pending is not None) + int(active is not None) <= 2
        if edge == 0:
            assert active is None  # Sync mientras W0 permanece en PENDING.
        if edge == length:
            assert active == source[-1] and pending is None
    assert result == source
    assert retained_data == source[-1][0]  # No borrar A_DATA al retirar validez.
    for byte in (retained_data & 255, retained_data >> 8):
        trail_byte = 255 if not (byte & 128) else 0
        assert all(((trail_byte >> i) & 1) != ((byte >> 7) & 1)
                   for i in range(8))


if __name__ == '__main__':
    check_profile()
    for n in (1, 2, 3, 4, 5, 9, 10, 4000):
        assert expiration(n) == n
    # Exit empieza junto a POST: a los 4 ciclos quedan 5 intervalos POST.
    post_remaining = 8
    for boundary in range(1, 10):
        if boundary == 4:
            assert post_remaining + 1 == 6  # Antes del flanco: intervalo 4.
        due = post_remaining == 0
        assert due == (boundary == 9)
        post_remaining = max(0, post_remaining - 1)
        if boundary == 4:
            assert post_remaining + 1 == 5  # Tras el flanco, hasta frontera 9.
    for n in (1, 2, 3, 4, 1083, 2048):
        check_schedule(n)
        pipeline(n)
    assert [(0xb8 >> i) & 1 for i in range(8)] == [0, 0, 0, 1, 1, 1, 0, 1]
    for last0 in (0, 1):
        for last1 in (0, 1):
            a = (last1 << 15) | (last0 << 7)
            trail = ((255 if not (a & 0x8000) else 0) << 8) | (255 if not (a & 0x80) else 0)
            assert (trail & 255) == (255 if last0 == 0 else 0)
            assert (trail >> 8) == (255 if last1 == 0 else 0)
    print('PASS: 8 duraciones; POST concurrente; 6 pipelines; Sync; 4 casos Trail')
