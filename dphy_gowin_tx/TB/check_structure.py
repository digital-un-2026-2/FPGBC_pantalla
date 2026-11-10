"""Check storage budget and primitive boundaries, without claiming pad timing."""
from collections import Counter
import json
import sys
m = json.load(open(sys.argv[1], encoding='utf-8'))['modules']['dphy_gowin_tx']
counts = Counter(c['type'] for c in m['cells'].values())
assert counts['OSER8'] == 3 and counts['TBUF'] == 6 and counts['TLVDS_TBUF'] == 3
assert counts['rPLL'] == 1
ff = dp = uc = 0
for c in m['cells'].values():
    kind = c['type']
    assert 'latch' not in kind.lower() and not kind.startswith('$mem'), kind
    if 'dff' not in kind.lower():
        continue
    params = c['parameters']
    assert int(params['CLK_POLARITY'], 2) == 1
    width = int(params['WIDTH'], 2)
    q = set(c['connections']['Q'])
    names = [name for name, net in m['netnames'].items() if set(net['bits']) == q]
    ff += width
    if any(name in ('dp.frame_q', 'dp.ctrl[0]', 'dp.ctrl[1]') for name in names):
        assert kind in ('$dff', '$dffe', '$sdff', '$sdffe', '$sdffce'), kind
        assert c['connections']['CLK'] == m['ports']['byte_clk']['bits']
        dp += width
    if any(name in ('uc.state', 'uc.run_started', 'uc.abort_seen', 'uc.clock_fault') for name in names):
        uc += width
assert (dp, uc, ff) == (52, 6, 79), (dp, uc, ff)
print('PASS structure: 52 datapath bits, 6 UC bits, 21 safety/CDC bits; 3 OSER8, 6 TBUF, 3 TLVDS_TBUF, 1 rPLL; no latches/RAM')
