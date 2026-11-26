# Objetivos de frecuencia de la sonda, sin prueba de fase ni de márgenes de E/S.
create_clock -period 25 [get_ports CLK_REF]
create_clock -period 18.181818 [get_nets CLK_BYTE]
create_clock -period 4.545455 [get_nets CLK_HS]
create_clock -period 9.090909 [get_nets forwarded.PCLK_110]
