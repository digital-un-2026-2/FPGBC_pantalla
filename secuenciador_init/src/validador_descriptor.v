module validador_descriptor (
    input wire [4:0] paso,
    input wire [7:0] base_activa,
    input wire [4:0] longitud_activa,

    output wire descriptor_valido
);

   wire [8:0] fin_exclusivo;

  // Ampliar ANTES de sumar para no perder un posible acarreo.
  assign fin_exclusivo = {1'b0, base_activa} + {4'b0000, longitud_activa};

  assign descriptor_valido =
         (paso <= 5'd17) &&
         (longitud_activa != 5'd0) &&
         (longitud_activa <= 5'd22) &&
         (fin_exclusivo <= 9'd204);

endmodule
