module validador_descriptor (
    input wire [3:0] paso,
    input wire [6:0] base_activa,
    input wire [3:0] longitud_activa,

    output wire descriptor_valido
);

  wire [7:0] fin_exclusivo;

  // Ampliar ANTES de sumar para no perder un posible acarreo.
  assign fin_exclusivo = {1'b0, base_activa} + {4'b0000, longitud_activa};

  assign descriptor_valido =
        (paso <= 4'd10) &&
        (longitud_activa != 4'd0) &&
        (fin_exclusivo <= 8'd75);

endmodule
