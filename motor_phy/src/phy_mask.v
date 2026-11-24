// Máscara B del datapath. No espera al próximo flanco de reloj.
module phy_mask (
    input rst,
    input preparar_lp,
    input fallo_init,
    input estado_valido,
    input fallo_activo,
    input en_lp,
    input sel_d0,
    input listo_ctrl,

    output sel,
    output [2:0] lp_oe,
    output lp_preparada
);
  wire b = preparar_lp & !rst & !fallo_init & estado_valido & !fallo_activo;

  assign sel = sel_d0 & b;
  assign lp_oe = {3{en_lp & b}};
  assign lp_preparada = listo_ctrl & b;
endmodule
