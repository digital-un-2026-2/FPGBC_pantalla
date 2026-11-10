from migen import ClockDomain, Module, Signal


class CRG(Module):
    def __init__(self, platform):
        self.clock_domains.cd_sys = ClockDomain("sys")
        self.clock_domains.cd_por = ClockDomain("por", reset_less=True)

        clk40 = platform.request("clk40")

        self.comb += [
            self.cd_sys.clk.eq(clk40),
            self.cd_por.clk.eq(clk40),
        ]

        contador_arranque = Signal(4, reset=0)

        self.sync.por += contador_arranque.eq(
            contador_arranque + (contador_arranque != 15)
        )

        self.comb += self.cd_sys.rst.eq(contador_arranque != 15)
