"""Reuse the packet stimulus/decoders, insert real wrapper and observe its pads.

No copy of the upstream testbench is maintained. All substitutions are checked.
The only non-RTL components in this link are the ideal cells in TB/.
"""
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
s = (root/'dphy_hs_tx/TB/hs_phy_link_TB.v').read_text()

def replace(old, new):
    global s
    assert s.count(old) == 1, old
    s = s.replace(old, new)

replace('module hs_phy_link_TB;', 'module gowin_link_TB;')
replace('  reg clk = 0;\n  always #12.5 clk = ~clk;\n  reg rst = 1;', '''  reg ref_clk=0, system_rst=1;
  always #12.5 ref_clk=~ref_clk;
  wire clk, rst_byte;
  wire rst=system_rst|rst_byte;''')
replace('  wire [1:0] lp;', '  wire [1:0] lp, lp_motor;')
replace('  wire stop_ready = local_stop && !lp_grant && (lp == 2\'b11);\n  reg pll_locked=1;',
        '  wire stop_ready, pll_locked, clock_fault;')
replace('transport_error || phy_error;', 'transport_error || phy_error || clock_fault;')
replace('.estado_D0(lp)', '.estado_D0(lp_motor)')
start=s.index('  dphy_hs_tx phy(')
end=s.index('  reg [7:0] expected_bytes', start)
instance=s[start:end]
ports={'clk_prepared':'clk_prepared','data_prepared':'data_prepared','data_stopped':'data_stopped',
       'clk_stopped':'clk_stopped','hs_local_stop':'local_stop','hs_frame_data':'frame',
       'hs_frame_kind':'frame_kind','hs_clk_on':'mock_clk_active','hs_data_on':'mock_data_active',
       'clk_toggle':'clk_toggle','lp_clk':'lp_clock','lp_d0':'lp_data0','lp_d1':'lp_data1'}
for port, net in ports.items():
    old=f'.{port}({net})'
    assert instance.count(old)==1, old
    instance=instance.replace(old,f'.{port}(raw_{net})')
decls='''  localparam J=`GOWIN_MODEL_J, L=2+J;
  wire [15:0] raw_frame;
  wire [1:0] raw_frame_kind,raw_lp_clock,raw_lp_data0,raw_lp_data1;
  wire raw_clk_prepared,raw_data_prepared,raw_data_stopped,raw_clk_stopped;
  wire raw_local_stop,raw_mock_clk_active,raw_mock_data_active,raw_clk_toggle;
  wire [2:0] lp_p,lp_n,hs_p,hs_n;
  assign lp={lp_p[0],lp_n[0]};
  assign local_stop=stop_ready;
  assign mock_clk_active=(hs_p[2]!==1'bz);
  assign mock_data_active=(hs_p[0]!==1'bz);
  // Expected phase tags only; serial data and clock come exclusively from pads.
  reg [2:0] expected_tags[0:L-1];
  integer stage;
  always @(posedge clk) begin
    if(rst || phy_abort) for(stage=0;stage<L;stage=stage+1) expected_tags[stage]<=0;
    else begin
      expected_tags[0]<={raw_clk_toggle,raw_frame_kind};
      for(stage=1;stage<L;stage=stage+1) expected_tags[stage]<=expected_tags[stage-1];
    end
  end
  assign {clk_toggle,frame_kind}=expected_tags[L-1];
  dphy_gowin_tx #(.J(J),.PROFILE_OK(1)) wrapper (
      .ref_clk(ref_clk),.rst(system_rst),.phy_abort(phy_abort),.lp_grant(lp_grant),.estado_D0(lp_motor),
      .hs_frame_data(raw_frame),.hs_frame_kind(raw_frame_kind),
      .hs_data_on(raw_mock_data_active),.hs_clk_on(raw_mock_clk_active),.clk_toggle(raw_clk_toggle),
      .lp_clk(raw_lp_clock),.lp_d0(raw_lp_data0),.lp_d1(raw_lp_data1),
      .clk_prepared_s(raw_clk_prepared),.data_prepared_s(raw_data_prepared),
      .data_stopped_s(raw_data_stopped),.clk_stopped_s(raw_clk_stopped),.local_stop_s(raw_local_stop),
      .byte_clk(clk),.rst_byte(rst_byte),
      .clk_prepared_p(clk_prepared),.data_prepared_p(data_prepared),
      .data_stopped_p(data_stopped),.clk_stopped_p(clk_stopped),
      .stop_ready(stop_ready),.pll_ready(pll_locked),.clock_fault(clock_fault),
      .lp_pad_p(lp_p),.lp_pad_n(lp_n),.hs_pad_p(hs_p),.hs_pad_n(hs_n));
'''
s=s[:start]+decls+instance+s[end:]
start=s.index('  localparam real UI=')
end=s.index('  reg [7:0] shift0=',start)
s=s[:start]+'''  wire serial_clock=(hs_p[2]===1'b1);
  wire serial_d0=hs_p[0],serial_d1=hs_p[1];
'''+s[end:]
replace('if (rst) begin\n      previous_lp', "if (rst || lp===2'bzz) begin\n      previous_lp")
replace("(lp !== 2'b11 && (mock_clk_active || mock_data_active || hs_grant))",
        "(lp_motor !== 2'b11 && (mock_clk_active || mock_data_active || hs_grant))")
replace('    end else if (lp === previous_lp)',
        "    end else if (!lp_grant && run_count==0) begin\n      previous_lp=2'b11;run_cycles=0;\n    end else if (lp === previous_lp)")
replace('drive; rst=0;', 'drive; system_rst=0;')
replace('$dumpvars(0, hs_phy_link_TB);', '$dumpvars(0, gowin_link_TB);')
replace('PASS PHY link:', 'PASS Gowin pads link:')
Path(sys.argv[1]).write_text(s)
