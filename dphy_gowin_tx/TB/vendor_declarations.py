"""Extract the four used declarations; whole GW2A libraries contain duplicates.

These declarations check ports/parameters only, never primitive timing.
"""
from pathlib import Path
import re
import sys
lib, out = map(Path, sys.argv[1:])
common = (lib / 'cells_sim.v').read_text()
extra = (lib / 'cells_xtra_gw2a.v').read_text()
blocks = ['`timescale 1ns/1ps\n']
for name, source in [('OSER8', common), ('rPLL', common), ('TBUF', common), ('TLVDS_TBUF', extra)]:
    match = re.search(r'^module\s+' + name + r'\s*[#(].*?^endmodule', source, re.M | re.S)
    if not match:
        raise RuntimeError(f'Missing installed declaration: {name}')
    blocks.append('(* blackbox *)\n' + match.group() + '\n')
out.write_text('\n'.join(blocks))
