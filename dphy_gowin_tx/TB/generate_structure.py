"""Build a synthesizable integration harness from the tested fault-link wiring."""
from pathlib import Path
import sys
s = Path(__file__).with_name('gowin_fault_link_TB.v').read_text().split('  task blocked;')[0]+'endmodule\n'
changes = {
    'module gowin_fault_link_TB;': 'module gowin_link_structure(input ref_clk, system_rst, valid, last, inject_error, input [1:0] keep, output complete);',
    '  localparam J=`GOWIN_MODEL_J;': '  localparam J=0;',
    '  reg ref_clk=0, system_rst=1;\n  always #12.5 ref_clk=~ref_clk;\n': '',
    '  reg valid=0,last=0,inject_error=0;\n  reg [1:0] keep=3;\n': '',
    'done,complete,transport_error': 'done,transport_error',
}
for old, new in changes.items():
    assert s.count(old) == 1, old
    s = s.replace(old, new)
Path(sys.argv[1]).write_text(s)
