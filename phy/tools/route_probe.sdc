# Objetivos de frecuencia; no acreditan la fase ni el setup/hold de las E/S.
create_clock -period 25 [get_ports CLK_REF]
create_clock -period 18.181818 [get_nets CLK_BYTE]
create_clock -period 4.545455 [get_nets link.CLK_HS]
create_clock -period 9.090909 [get_nets link.forwarded.PCLK_110]
