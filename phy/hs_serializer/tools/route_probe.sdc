# Objetivos nominales de la sonda; no representan la fase ni los márgenes de E/S.
create_clock -period 25 [get_ports CLK_REF]
create_clock -period 18.181818 [get_nets CLK_BYTE]
create_clock -period 4.5454545 [get_nets CLK_HS]
