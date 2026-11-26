"""Audita la implementación del TOP LP/HS y sus fusibles DSI en memoria."""

import argparse
import json
from pathlib import Path
import re

from gateware.tests.review_io import BACKLIGHT_PINS, DEVICE, expected_bel, io_attribute, load_reference
from phy.dphy_pads.tools.verify_route import audit_fuses, require, route_pips, verify_route


def verify_board_pins(top, db):
    package, device, _ = db.packages[DEVICE]
    pins = db.pinout[device][package]
    expected = (
        ("clk40", 11, "clk40_buf", "IBUF", "I", "LVCMOS33", None),
        ("global_rst_n", 120, "reset_buf", "IBUF", "I", "LVCMOS25", "UP"),
        ("backlight_en", BACKLIGHT_PINS["backlight_en"][0], "en_buf", "OBUF", "O", "LVCMOS33", "NONE"),
        ("backlight_pwm", BACKLIGHT_PINS["backlight_pwm"][0], "pwm_buf", "OBUF", "O", "LVCMOS33", "NONE"),
    )
    for port, number, name, primitive, terminal, standard, pull in expected:
        cell = top["cells"][name]
        bel, *_ = expected_bel(db, pins[str(number)][0])
        require(cell["type"] == primitive and cell["attributes"]["NEXTPNR_BEL"] == bel
                and cell["connections"][terminal] == top["ports"][port]["bits"]
                and io_attribute(cell, "IO_TYPE") == standard
                and io_attribute(cell, "PULL_MODE") == pull,
                f"{port}: pin, buffer o atributos incorrectos")


def verify_board_clocks(top):
    cells, nets = top["cells"], top["netnames"]
    pll = cells["link.clocks.pll"]["connections"]
    require(pll["CLKIN"] == cells["clk40_buf"]["connections"]["O"] == nets["ref_clk"]["bits"],
            "La referencia de la PLL no viene del pin de 40 MHz")
    require(pll["RESET"] == nets["reset_pll"]["bits"] and pll["RESET"] != nets["rst_byte"]["bits"],
            "Se mezclaron el reset de PLL y el reset de byte")
    require(pll["LOCK"] == nets["lock_raw"]["bits"], "LOCK_RAW no sale de la PLL")

    watchdog = cells["supervisor.watchdog_clock"]
    oscillator = cells["supervisor.oscillator"]
    wd_net = nets["supervisor.CLK_WD"]
    site = watchdog["attributes"]["NEXTPNR_BEL"].split("/")[0]
    require(oscillator["type"] == "OSC" and watchdog["type"] == "BUFG"
            and oscillator["connections"]["OSCOUT"] == wd_net["bits"]
            and watchdog["connections"]["I"] == nets["supervisor.OSC_CLK"]["bits"]
            and any(pip.startswith(f"{site}/CLK") for pip in route_pips(wd_net))
            and any(re.search(r"/SPINE\d+/BLBDCLK\d+$", pip) for pip in route_pips(wd_net)),
            "CLK_WD no entra en la red global por OSC y BUFG")

    for clock in ("ref_clk", "clk_byte", "supervisor.CLK_WD", "link.CLK_HS", "link.forwarded.PCLK_110"):
        net = nets[clock]
        global_sites = {
            pip.split("/")[0] for pip in route_pips(net)
            if re.search(r"/CLK[0-2]/GB[0-7]0$", pip)
        }
        sinks = [
            (name, cell) for name, cell in cells.items()
            if cell["type"].startswith("DFF") and cell["connections"].get("CLK") == net["bits"]
        ]
        require(sinks, f"{clock}: sin registros asociados")
        for name, cell in sinks:
            require(cell["attributes"]["NEXTPNR_BEL"].split("/")[0] in global_sites,
                    f"{clock}: {name} sin conexión de reloj global")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("variant", choices=("direct", "delay"))
    args = parser.parse_args()
    routed = args.build / "fpgbc_white_routed.json"
    top = json.loads(routed.read_text())["modules"]["top"]
    db, _, provenance = load_reference()
    verify_board_pins(top, db)
    verify_board_clocks(top)

    # nextpnr conserva un solo nombre para cada red. Presentar las señales
    # de frontera del TOP con los nombres que usa la auditoría DPHY_PADS.
    phy_view = {
        **top,
        **{key: {name.removeprefix("link."): entry for name, entry in top[key].items()}
           for key in ("cells", "netnames")},
    }
    for expected, actual in (("CLK_BYTE", "clk_byte"), ("ISO", "iso")):
        phy_view["netnames"][expected] = top["netnames"][actual]
    pads = verify_route(phy_view, db, args.variant)
    print("PASS TOP: pines, relojes dedicados, serializadores locales y OEN dominados por ISO")

    report = audit_fuses(routed, pads, provenance)
    output = args.build / "fuse_review.json"
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    require(not report["errors"], "\n".join(report["errors"]))
    print(f"PASS fusibles DSI en memoria: {output}")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, ValueError) as error:
        raise SystemExit(f"Fallo en la auditoría del TOP: {error}") from error
