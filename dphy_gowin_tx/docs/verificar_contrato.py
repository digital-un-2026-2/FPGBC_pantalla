"""Comprueba el contrato de retardo con la integración RTL existente.

Retarda 32 bits de tramas/controles/ACK del secuenciador; conserva el monitor
serial independiente y la ruta LPDT lógica del testbench original. No modela
OSER8, PLL, pads ni la retimización física LPDT. Requiere iverilog y vvp.
"""
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[2]
original=(root/'dphy_hs_tx/TB/hs_phy_link_TB.v').read_text()
start=original.index('  dphy_hs_tx phy(')
end=original.index('  reg [7:0] expected_bytes',start)
ports={'clk_prepared':'clk_prepared','data_prepared':'data_prepared','data_stopped':'data_stopped','clk_stopped':'clk_stopped','hs_local_stop':'local_stop','hs_frame_data':'frame','hs_frame_kind':'frame_kind','hs_clk_on':'mock_clk_active','hs_data_on':'mock_data_active','clk_toggle':'clk_toggle','lp_clk':'lp_clock','lp_d0':'lp_data0','lp_d1':'lp_data1'}
instance=original[start:end]
for port,net in ports.items():
 old=f'.{port}({net})'
 assert instance.count(old)==1,old
 instance=instance.replace(old,f'.{port}(raw_{net})')
names=['lp_clock','lp_data0','lp_data1','frame','frame_kind','mock_clk_active','mock_data_active','clk_toggle','clk_prepared','data_prepared','data_stopped','clk_stopped','local_stop']
widths=[2,2,2,16,2,1,1,1,1,1,1,1,1]
assert sum(widths)==32
rtl=[]
for d in ['dphy_hs_tx','dsi_lp_packet_tx','dsi_long_packet_tx','dsi_lane_packer','dsi_hs_transport','dphy_mode_ctrl','dsi_lpdt_bridge','dphy_lpdt_tx']:
 rtl+=sorted(str(p) for p in (root/d/'src').glob('*.v'))
with tempfile.TemporaryDirectory(prefix="gowin-contrato-") as work:
    for latency in (2,5):
     decl=''.join(f'  wire [{w-1}:0] raw_{n};\n' for n,w in zip(names,widths))
     decl+=f'  reg [31:0] command_pipe[0:{latency-1}];\n  integer stage;\n'
     decl+='  always @(posedge clk) begin\n    if(rst || phy_abort) begin\n'
     decl+=f'      for(stage=0;stage<{latency};stage=stage+1) command_pipe[stage]<=0;\n'
     decl+='    end else begin\n      command_pipe[0]<={'+','.join('raw_'+n for n in names)+'};\n'
     decl+=f'      for(stage=1;stage<{latency};stage=stage+1) command_pipe[stage]<=command_pipe[stage-1];\n'
     decl+='    end\n  end\n  assign {'+','.join(names)+f'}}=command_pipe[{latency-1}];\n'
     tb=Path(work)/f'gowin_retardo_L{latency}_TB.v'
     tb.write_text(original[:start]+decl+instance+original[end:])
     exe=str(Path(work)/f'gowin_retardo_L{latency}')
     compile_result=subprocess.run(['iverilog','-g2012','-s','hs_phy_link_TB','-o',exe,str(tb),*rtl],capture_output=True,text=True)
     if compile_result.returncode: raise RuntimeError(compile_result.stderr)
     run=subprocess.run(['vvp',exe],capture_output=True,text=True)
     print(f'L={latency}: {run.stdout.strip()}')
     if run.returncode: raise RuntimeError(run.stderr or run.stdout)
