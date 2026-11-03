// Interfaz LP combinacional. El motor debe estar inicializado en LP-11
// ANTES de preparar_lp. No hay FSM, receptor, BTA ni registros adicionales.
module fisical_layer (
    input preparar_lp,
    input rst_motor,
    input [1:0] estado_D0,
    input liberar_d0,

    output lp_preparada,
    output d0_pad_p,
    output d0_pad_n,
    output [5:0] hs_oen,

    inout D0_P,
    inout D0_N,
    output CLK_P,
    output CLK_N,
    output D1_P,
    output D1_N,
    output [5:0] hs_pads
);

  wire habilitar_lp;
  wire lp_aux_oen;
  wire d0_oen;

  assign habilitar_lp = preparar_lp & ~rst_motor;
  assign lp_aux_oen = ~habilitar_lp;
  assign d0_oen = lp_aux_oen | liberar_d0;
  assign lp_preparada = ~d0_oen;
  assign hs_oen = 6'b111111;

  IOBUF d0_p_buffer (
      .I(estado_D0[1]), .OEN(d0_oen), .IO(D0_P), .O(d0_pad_p)
  );
  IOBUF d0_n_buffer (
      .I(estado_D0[0]), .OEN(d0_oen), .IO(D0_N), .O(d0_pad_n)
  );

  TBUF clk_p_buffer (.I(1'b1), .OEN(lp_aux_oen), .O(CLK_P));
  TBUF clk_n_buffer (.I(1'b1), .OEN(lp_aux_oen), .O(CLK_N));
  TBUF d1_p_buffer  (.I(1'b1), .OEN(lp_aux_oen), .O(D1_P));
  TBUF d1_n_buffer  (.I(1'b1), .OEN(lp_aux_oen), .O(D1_N));

  // Controlar todas las ramas HS, incluso sin implementar transporte HS.
  // Revisar primitivas, constraints y estado efectivo antes de usar en placa.
  genvar rama;
  generate
    for (rama = 0; rama < 6; rama = rama + 1) begin : hs_deshabilitada
      TBUF hs_buffer (.I(1'b0), .OEN(hs_oen[rama]), .O(hs_pads[rama]));
    end
  endgenerate

endmodule
