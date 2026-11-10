"""Elaborate an enabled synthetic schedule so optimization cannot hide wiring."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
build = root / "build" / "dsi_display"
directories = (
    "dsi_display", "dsi_video_scheduler", "dsi_test_pattern", "dsi_long_packet_tx",
    "dsi_lp_packet_tx", "dsi_lane_packer", "dsi_hs_transport", "dsi_lpdt_bridge",
    "dphy_lpdt_tx", "dphy_mode_ctrl", "dphy_hs_tx", "dphy_gowin_tx",
)
sources = " ".join(str(path) for directory in directories for path in sorted((root / directory / "src").glob("*.v")))
events = sum(((kind << 64) | 1000) << (66 * n) for n, kind in enumerate((0, 1, 2)))
elaborate = (
    f"read_verilog {sources}; "
    "chparam -set WIDTH 8 -set HEIGHT 1 -set BUFFER_WORDS 32 -set E_MAX 3 "
    "-set N_EVENTS_TABLE 3 -set T_FRAME_TABLE 1000 -set TIMING_OK_TABLE 1 "
    f"-set TARGET_OK_TABLE 1 -set EVENT_TABLE 198'd{events} -set PROFILE_OK 1 dsi_display_top; "
)
script = (
    f"read_verilog -lib {root}/build/dphy_gowin_tx/gowin_declarations.v; " + elaborate +
    "hierarchy -check -top dsi_display_top; proc; flatten; opt; check -assert; "
    "scc -expect 0; select -assert-none t:$dlatch; stat"
)
with (build / "structure.log").open("w") as output:
    subprocess.run(["yosys", "-Q", "-T", "-p", script], stdout=output, stderr=subprocess.STDOUT, check=True)
print("PASS display structure: enabled scheduler and PHY, no latches or combinational loops")
with (build / "synth.log").open("w") as output:
    subprocess.run(["yosys", "-Q", "-T", "-p", elaborate +
                    f"synth_gowin -family gw2a -top dsi_display_top -json {build}/gowin.json"],
                   stdout=output, stderr=subprocess.STDOUT, check=True)
print("PASS display synth_gowin: full enabled chain, GW2A mapping (without P&R/STA)")
