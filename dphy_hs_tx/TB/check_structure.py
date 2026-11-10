"""Inspect the flattened generic netlist; no Gowin mapping is asserted."""
import json,sys
m=json.load(open(sys.argv[1],encoding='utf-8'))['modules']['dphy_hs_tx']
width=0
for cell in m.get('cells',{}).values():
    kind=cell['type'];params=cell.get('parameters',{})
    assert 'latch' not in kind.lower(),kind
    assert not kind.startswith('$mem'),kind
    if 'dff' in kind.lower():
        assert kind in ('$dff','$dffe','$sdff','$sdffe','$sdffce'),kind
        assert int(params['CLK_POLARITY'],2)==1
        width+=int(params['WIDTH'],2)
assert width==60,width
print('PASS structure: 60 FF bits, posedge, no latches, RAM or asynchronous resets')
