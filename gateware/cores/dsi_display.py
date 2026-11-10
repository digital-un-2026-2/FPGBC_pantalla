"""CSR adapter for the complete DSI chain; reference/control clock is sys=40MHz."""
from pathlib import Path

from migen import Cat, ClockSignal, If, Instance, Module, ResetSignal, Signal
from migen.genlib.cdc import MultiReg
from litex.soc.interconnect.csr import AutoCSR, CSRStatus, CSRStorage


class DSIDisplay(Module, AutoCSR):
    def __init__(self, platform, *, pads=None, rtl_parameters=None,
                 module_name="dsi_display_top", reset_initial=1):
        parameters = dict(rtl_parameters or {})
        # This adapter has no characterized panel profile. A caller supplying
        # one must also explicitly supply the corresponding platform pads.
        if parameters.get("PROFILE_OK", 0) and pads is None:
            raise ValueError("PROFILE_OK requiere pads y un perfil físico caracterizado")
        self.reset = CSRStorage(1, reset=reset_initial, name="reset")
        self.command = CSRStorage(32, name="command")
        self.clear = CSRStorage(1, name="clear")
        self.bridge = CSRStatus(7, name="bridge")
        self.sequence = CSRStatus(32, name="sequence")
        self.flags = CSRStatus(32, name="flags")
        self.frames = CSRStatus(32, name="frames")
        self.lp_completed = CSRStatus(32, name="lp_completed")
        self.geometry = CSRStatus(32, name="geometry")

        self.command_ready = Signal()
        self.command_valid = Signal()
        self.response_valid = Signal()
        self.response = Signal(128)
        self.byte_clk = Signal()
        self.byte_rst = Signal()
        self.phy_available = Signal()
        self.clock_fault = Signal()
        self.lp_pad_p, self.lp_pad_n = Signal(3), Signal(3)
        self.hs_pad_p, self.hs_pad_n = Signal(3), Signal(3)
        available, fault, byte_reset = Signal(), Signal(), Signal(reset=1)
        self.specials += [
            MultiReg(self.phy_available, available),
            MultiReg(self.clock_fault, fault),
            MultiReg(self.byte_rst, byte_reset, reset=1),
        ]
        pending, result_valid, rejected = Signal(), Signal(), Signal()
        can_send = Signal()
        self.comb += [
            can_send.eq(self.command_ready & ~pending & ~self.reset.storage & ~byte_reset),
            self.command_valid.eq(self.command.wr_stb & can_send),
            self.bridge.status.eq(Cat(can_send, result_valid, rejected, available, fault, byte_reset, pending)),
        ]
        self.sync += [
            If(self.reset.storage | byte_reset,
                pending.eq(0), result_valid.eq(0), rejected.eq(0),
                self.sequence.status.eq(0), self.flags.status.eq(0),
                self.frames.status.eq(0), self.lp_completed.status.eq(0), self.geometry.status.eq(0),
            ).Else(
                If(self.clear.wr_stb & self.clear.storage, rejected.eq(0)),
                If(self.command.wr_stb,
                    If(can_send, pending.eq(1), result_valid.eq(0)).Else(rejected.eq(1))),
                If(self.response_valid,
                    pending.eq(0), result_valid.eq(1),
                    self.sequence.status.eq(self.sequence.status + 1),
                    self.flags.status.eq(self.response[:32]),
                    self.frames.status.eq(self.response[32:64]),
                    self.lp_completed.status.eq(self.response[64:96]),
                    self.geometry.status.eq(self.response[96:128]),
                ),
            )
        ]
        self.specials += Instance(
            module_name,
            **{"p_" + name: value for name, value in parameters.items()},
            i_ref_clk=ClockSignal("sys"), i_rst=ResetSignal("sys") | self.reset.storage,
            i_command=self.command.storage, i_command_valid=self.command_valid,
            o_command_ready=self.command_ready, o_response=self.response, o_response_valid=self.response_valid,
            o_byte_clk=self.byte_clk, o_rst_byte=self.byte_rst,
            o_phy_available=self.phy_available, o_clock_fault=self.clock_fault,
            o_lp_pad_p=self.lp_pad_p, o_lp_pad_n=self.lp_pad_n,
            o_hs_pad_p=self.hs_pad_p, o_hs_pad_n=self.hs_pad_n,
        )
        if pads is not None:
            self.comb += [
                pads.lp_p.eq(self.lp_pad_p), pads.lp_n.eq(self.lp_pad_n),
                pads.hs_p.eq(self.hs_pad_p), pads.hs_n.eq(self.hs_pad_n),
            ]
        root = Path(__file__).resolve().parents[2]
        for directory in (
            "dsi_display", "dsi_video_scheduler", "dsi_test_pattern", "dsi_long_packet_tx",
            "dsi_lp_packet_tx", "dsi_lane_packer", "dsi_hs_transport", "dsi_lpdt_bridge",
            "dphy_lpdt_tx", "dphy_mode_ctrl", "dphy_hs_tx", "dphy_gowin_tx",
        ):
            for source in sorted((root / directory / "src").glob("*.v")):
                platform.add_source(str(source))
