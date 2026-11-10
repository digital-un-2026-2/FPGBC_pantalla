"""Test data describes raw DCS commands, not the packet encoding under test."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
build = root / "build/dsi_display"
build.mkdir(parents=True, exist_ok=True)
steps = json.loads((root / "profiles/lt031mdz4000_init.json").read_text())["steps"]
steps += json.loads((root / "profiles/lt031mdz4000_backlight.json").read_text())["steps"]
lines = ["function [7:0] init_payload_ref(input integer step, input integer pos);",
         "begin init_payload_ref=0;case(step*16+pos)"]
for n, step in enumerate(steps):
    for p, value in enumerate([step["opcode"]] + step["params"]):
        lines.append(f"{n*16+p}: init_payload_ref=8'h{value:02x};")
lines += ["default: init_payload_ref=0;endcase end endfunction",
          "function integer init_params_ref(input integer step);begin case(step)"]
for n, step in enumerate(steps):
    lines.append(f"{n}: init_params_ref={len(step['params'])};")
lines += ["default: init_params_ref=0;endcase end endfunction",
          "function integer init_delay_ref(input integer step);begin case(step)"]
for n, step in enumerate(steps):
    lines.append(f"{n}: init_delay_ref={step['delay_ms']};")
lines += ["default: init_delay_ref=0;endcase end endfunction", ""]
(build / "image_init_reference.vh").write_text("\n".join(lines))
