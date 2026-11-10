"""Generate the real Migen/LiteX CSR adapter for an Icarus integration test."""
from pathlib import Path
import sys
from types import SimpleNamespace

from migen import ClockDomain, Constant, Module, Signal
from migen.fhdl import verilog
from litex.soc.interconnect.csr_bus import CSRBank, Interface

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root))
from gateware.cores.dsi_display import DSIDisplay

build = root / "build" / "dsi_display"
build.mkdir(parents=True, exist_ok=True)
sources = []
platform = SimpleNamespace(add_source=sources.append)
pads = SimpleNamespace(**{name: Signal(3, name_override="test_" + name)
                          for name in ("lp_p", "lp_n", "hs_p", "hs_n")})
events = sum(((kind << 64) | (100 if n == 0 else 1000)) << (66*n)
             for n, kind in enumerate((0, 1, 2)))
module = Module()
module.clock_domains.cd_sys = ClockDomain("sys")
module.submodules.display = display = DSIDisplay(platform, pads=pads, rtl_parameters={
    "WIDTH": 8, "HEIGHT": 1, "BUFFER_WORDS": 32, "E_MAX": 3,
    "N_EVENTS_TABLE": 3, "T_FRAME_TABLE": 1000,
    "TIMING_OK_TABLE": 1, "TARGET_OK_TABLE": 1,
    "EVENT_TABLE": Constant(events, 198), "PROFILE_OK": 1,
})
bus = Interface(data_width=32)
for name in ("adr", "dat_w", "dat_r", "re", "we"):
    getattr(bus, name).name_override = "csr_" + name
csrs = display.get_csrs()
module.submodules.bank = CSRBank(csrs, bus=bus)
io = {module.cd_sys.clk, module.cd_sys.rst, bus.adr, bus.dat_w, bus.dat_r, bus.re, bus.we}
(build / "display_csr.v").write_text(str(verilog.convert(module, ios=io, name="display_csr")))
(build / "csr_addresses.vh").write_text("".join(f"`define CSR_{reg.name.upper()} {n}\n" for n, reg in enumerate(csrs)))
(build / "csr_sources.txt").write_text("\n".join(sources))
