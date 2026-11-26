"""Exporta el TOP LP/HS de FPGBC para verificación offline."""

import argparse
from pathlib import Path

from migen import ClockDomain, Instance, Module, Signal

from gateware.cores.lp_init import ROOT
from gateware.platforms.fpgbc import Platform


class FPGBCWhiteTarget(Module):
    def __init__(self, platform, *, white=True, delay=False):
        self.clock_domains.cd_ref = ClockDomain("ref", reset_less=True)
        ref = self.cd_ref.clk
        reset_n = Signal(name="button_rst_n")
        clk_pad = platform.request("clk40")
        self.specials += [
            Instance("IBUF", name="clk40_buf", i_I=clk_pad, o_O=ref),
            Instance("IBUF", name="reset_buf", i_I=platform.request("global_rst_n"), o_O=reset_n),
        ]
        platform.add_period_constraint(clk_pad, platform.default_clk_period)
        byte = Signal(name="clk_byte")
        lock_raw = Signal(name="lock_raw")
        reset_pll = Signal(name="reset_pll")
        rst_sup = Signal(name="rst_sup")
        rst_byte = Signal(name="rst_byte")
        iso = Signal(name="iso")
        init_done = Signal(name="init_done")
        bl_en = Signal(name="bl_en")
        bl_pwm = Signal(name="bl_pwm")

        init_req, init_ready, init_next, init_last, init_done_tx = (
            Signal(name=name) for name in
            ("init_req", "init_ready", "init_next", "init_last", "init_done_tx")
        )
        init_byte = Signal(8, name="init_byte")
        vid_req, vid_line_rdy, vid_rd = (
            Signal(name=name) for name in ("vid_req", "vid_line_rdy", "vid_rd")
        )
        vid_word = Signal(16, name="vid_word")
        ready, lock, hs_req, clk_req = (
            Signal(name=name) for name in ("ready", "lock", "hs_req", "clk_req")
        )
        lp_p, lp_n = Signal(3, name="lp_p"), Signal(3, name="lp_n")
        hs_byte0, hs_byte1 = Signal(8, name="hs_byte0"), Signal(8, name="hs_byte1")
        byte_domain = dict(i_CLK_BYTE=byte, i_RST_BYTE=rst_byte)
        pads = {
            f"o_{mode}_{lane}_{side}": platform.request(f"{mode}_{lane}_{side}")
            for mode in ("LP", "HS") for lane in ("D0", "D1", "CLK") for side in "PN"
        }

        self.specials += [
            Instance("fpgbc_white_control", name="control", i_CLK_REF=ref, i_CLK_BYTE=byte,
                     i_GLOBAL_RST_N=reset_n, i_RST_BYTE=rst_byte, i_ISO=iso,
                     i_INIT_DONE=init_done, o_RST_SUP=rst_sup, o_BL_EN=bl_en, o_BL_PWM=bl_pwm),
            Instance("OBUF", name="en_buf", i_I=bl_en, o_O=platform.request("backlight_en")),
            Instance("OBUF", name="pwm_buf", i_I=bl_pwm, o_O=platform.request("backlight_pwm")),
            Instance("phy_supervisor", name="supervisor", i_CLK_REF=ref,
                     i_CLK_BYTE=byte, i_LOCK_RAW=lock_raw, i_RST_SUP=rst_sup, i_RST_LINK=0,
                     o_RESET=reset_pll, o_RST_BYTE=rst_byte),
            Instance("init_sequencer", name="seq", p_CLK_BYTE_HZ=55_000_000, **byte_domain,
                     o_INIT_REQ=init_req, i_INIT_READY=init_ready, i_INIT_NEXT=init_next,
                     o_INIT_LAST=init_last, o_INIT_BYTE=init_byte, i_INIT_DONE_TX=init_done_tx,
                     o_INIT_DONE=init_done),
            Instance("video_source", name="video", p_WHITE=Instance.PreformattedParam("1'b1" if white else "1'b0"),
                     **byte_domain, i_INIT_DONE=init_done, i_VID_RD=vid_rd,
                     o_VID_REQ=vid_req, o_VID_LINE_RDY=vid_line_rdy, o_VID_WORD=vid_word),
            Instance("mipi_tx", name="tx", p_LP_DIV=6, p_T_CLK_START=27, p_T_LPX=4,
                     p_T_PREP=3, p_T_ZERO=7, p_T_TRAIL=4, p_C_LINE=1166, **byte_domain,
                     i_INIT_REQ=init_req, o_INIT_READY=init_ready, o_INIT_DONE_TX=init_done_tx,
                     i_INIT_BYTE=init_byte, i_INIT_LAST=init_last, o_INIT_NEXT=init_next,
                     i_VID_REQ=vid_req, i_VID_LINE_RDY=vid_line_rdy, i_VID_WORD=vid_word, o_VID_RD=vid_rd,
                     i_READY=ready, i_LOCK=lock, o_HS_REQ=hs_req, o_CLK_REQ=clk_req,
                     o_LP_P=lp_p, o_LP_N=lp_n, o_HS_BYTE0=hs_byte0, o_HS_BYTE1=hs_byte1),
            Instance("phy", name="link", p_USE_IODELAY=Instance.PreformattedParam("1'b1" if delay else "1'b0"),
                     p_STATIC_DELAY_TAPS=32, i_CLK_REF=ref, i_RST_BYTE=rst_byte, i_RESET=reset_pll,
                     i_HS_REQ=hs_req, i_CLK_REQ=clk_req, i_LP_P=lp_p, i_LP_N=lp_n,
                     i_HS_BYTE0=hs_byte0, i_HS_BYTE1=hs_byte1, o_CLK_BYTE=byte, o_LOCK_RAW=lock_raw,
                     o_LOCK=lock, o_READY=ready, o_ISO=iso, **pads),
        ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/fpgbc_white/direct")
    parser.add_argument("--bars", action="store_true")
    parser.add_argument("--delay", action="store_true", help="Ensayar el IODELAY de 32 taps")
    args = parser.parse_args()

    platform = Platform(mixed_phy=True)
    # LiteX exports a build script too. Disable its packaging step for this target.
    platform.toolchain.packer_cmd = "false"
    platform.toolchain._synth_opts += " -nobram"
    platform.add_verilog_include_path(str(ROOT / "build/init_sequencer"))
    for pattern in ("phy/src/*.v", "phy/*/src/*.v", "mipi_tx/src/*.v",
                    "mipi_tx/*/src/*.v", "init_sequencer/src/*.v", "video_source/src/*.v"):
        for source in sorted(ROOT.glob(pattern)):
            platform.add_source(source)
    platform.add_source(ROOT / "motor_lpdt/src/reg_0.v")
    platform.add_source(ROOT / "gateware/cores/fpgbc_white_control.v")
    platform.build(FPGBCWhiteTarget(platform, white=not args.bars, delay=args.delay),
                   build_dir=str(args.output_dir), build_name="fpgbc_white",
                   run=False, timingstrict=True)


if __name__ == "__main__":
    main()
