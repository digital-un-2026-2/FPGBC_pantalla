# Perfil candidato; estas restricciones no certifican fase ni los cruces.
create_clock -period 25 [get_nets link.CLK_REF]
create_clock -period 18.181818 [get_nets link.CLK_BYTE]
create_clock -period 4.545455 [get_nets link.CLK_HS]
create_clock -period 9.090909 [get_nets link.forwarded.PCLK_110]
create_clock -period 32.258064 [get_nets supervisor.CLK_WD]
