`timescale 1ns / 1ps

module fisical_layer_TB;
  reg preparar_lp = 0;
  reg rst_motor = 1;
  reg liberar_d0 = 0;
  reg [1:0] estado_D0 = 2'bxx;
  tri D0_P, D0_N;
  wire CLK_P, CLK_N, D1_P, D1_N;
  tri [5:0] hs_pads;
  wire [5:0] hs_oen;
  wire d0_pad_p, d0_pad_n, lp_preparada;
  reg externo_habilitado = 0;
  reg [1:0] externo_d0 = 0;
  reg externo_hs_habilitado = 0;
  reg [5:0] externo_hs = 0;
  integer control, dato, externo;
  integer comprobaciones = 0;

  assign {D0_P, D0_N} = externo_habilitado ? externo_d0 : 2'bzz;
  // Los puertos HS aislados permiten detectar que el DUT nunca los conduce.
  assign hs_pads = externo_hs_habilitado ? externo_hs : 6'bzzzzzz;

  fisical_layer dut (
      .preparar_lp(preparar_lp), .rst_motor(rst_motor),
      .estado_D0(estado_D0), .liberar_d0(liberar_d0),
      .lp_preparada(lp_preparada), .d0_pad_p(d0_pad_p), .d0_pad_n(d0_pad_n),
      .hs_oen(hs_oen), .D0_P(D0_P), .D0_N(D0_N),
      .CLK_P(CLK_P), .CLK_N(CLK_N), .D1_P(D1_P), .D1_N(D1_N), .hs_pads(hs_pads)
  );

  task comprobar;
    reg activa, conduce;
    reg [1:0] esperado;
    begin
      #1;
      activa = preparar_lp && !rst_motor;
      conduce = activa && !liberar_d0;
      esperado = conduce ? estado_D0 : (externo_habilitado ? externo_d0 : 2'bzz);
      if ({D0_P, D0_N} !== esperado || {d0_pad_p, d0_pad_n} !== esperado)
        $fatal(1, "FAIL: D0/pads ctrl=%b%b%b dato=%b esperado=%b recibido=%b",
               rst_motor, preparar_lp, liberar_d0, estado_D0, esperado, {D0_P, D0_N});
      if ({CLK_P, CLK_N, D1_P, D1_N} !== (activa ? 4'b1111 : 4'bzzzz))
        $fatal(1, "FAIL: CLK/D1");
      if (lp_preparada !== conduce || dut.d0_oen !== !conduce || dut.lp_aux_oen !== !activa)
        $fatal(1, "FAIL: habilitaciones internas");
      if (hs_oen !== 6'b111111 || hs_pads !== (externo_hs_habilitado ? externo_hs : 6'bzzzzzz))
        $fatal(1, "FAIL: una rama HS conduce");
      comprobaciones = comprobaciones + 1;
    end
  endtask

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("fisical_layer_TB.fst");
      $dumpvars(0, fisical_layer_TB);
    end

    // Datos desconocidos antes de inicializar no salen de buffers deshabilitados.
    comprobar;
    for (control = 0; control < 8; control = control + 1) begin
      {rst_motor, preparar_lp, liberar_d0} = control[2:0];
      for (dato = 0; dato < 4; dato = dato + 1) begin
        estado_D0 = dato[1:0];
        externo_habilitado = 0;
        externo_hs_habilitado = 0;
        comprobar;
        if (rst_motor || !preparar_lp || liberar_d0) begin
          externo_habilitado = 1;
          for (externo = 0; externo < 4; externo = externo + 1) begin
            externo_d0 = externo[1:0];
            comprobar;
          end
          externo_habilitado = 0;
        end
        // Probar ambas polaridades externas detecta incluso un driver fijo.
        externo_hs_habilitado = 1;
        externo_hs = 6'b000000;
        comprobar;
        externo_hs = 6'b111111;
        comprobar;
        externo_hs_habilitado = 0;
      end
    end

    // Liberar ambos conductores a la vez, sin afectar CLK/D1.
    rst_motor = 0;
    preparar_lp = 1;
    liberar_d0 = 0;
    estado_D0 = 2'b10;
    comprobar;
    liberar_d0 = 1;
    comprobar;
    externo_habilitado = 1;
    externo_d0 = 2'b01;
    comprobar;
    // Solo la prueba autoriza volver a conducir; no hay recuperacion automatica.
    externo_habilitado = 0;
    liberar_d0 = 0;
    comprobar;
    rst_motor = 1;
    estado_D0 = 2'bxx;
    comprobar;

    $display("PASS: fisical_layer_TB; %0d comprobaciones, 32 combinaciones control/dato, pads y HS liberados", comprobaciones);
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "FAIL: timeout fisical_layer_TB");
  end
endmodule
