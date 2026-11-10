"""Use the installed nextpnr, including YoWASP, without changing the environment."""
from shutil import which
from pathlib import Path
import re

from litex.build.gowin.apicula import GowinApiculaToolchain


class FPGBCAPiculaToolchain(GowinApiculaToolchain):
    def __init__(self):
        super().__init__()
        self._synth_opts = " -family gw2a"

    def build_io_constraints(self):
        filename, kind = super().build_io_constraints()
        # nextpnr packs the individual P/N OBUFs before merging the TLVDS cell.
        # Unlike Gowin IDE's paired CST syntax, both ports need locations.
        path = Path(filename)

        def individual_pins(match):
            name, positive, negative = match.groups()
            n_name = name.replace("_p[", "_n[") if "_p[" in name else name[:-2] + "_n"
            return (f'IO_LOC "{name}" {positive};\n'
                    f'IO_LOC "{n_name}" {negative};\n'
                    f'IO_PORT "{n_name}" IO_TYPE=LVDS25 PULL_MODE=NONE;')

        path.write_text(re.sub(r'IO_LOC "([^"]+)" (\d+),(\d+);', individual_pins, path.read_text()))
        return filename, kind

    def finalize(self):
        super().finalize()
        if which(self._nextpnr.name) is None and which("yowasp-nextpnr-himbaechel-gowin"):
            self._nextpnr.name = "yowasp-nextpnr-himbaechel-gowin"
