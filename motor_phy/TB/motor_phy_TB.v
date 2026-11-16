`timescale 1ns/1ps
module motor_phy_TB;
  parameter integer N = 4;
  reg clk = 0;
  always #12.5 clk = ~clk;

  reg rst = 1;
  reg preparar_lp = 0;
  reg fallo_init = 0;
  reg [1:0] estado_D0 = 2'b00;
  wire lp_preparada;
  wire [2:0] lp_p, lp_n, lp_oe, hs_oen;
  wire [2:0] pads_p, pads_n, pads_hs_p, pads_hs_n;
  integer i, fase, codigo;
  time inicio;

  motor_phy #(.T_HABILITACION(N)) dut (
      .clk(clk), .rst(rst), .preparar_lp(preparar_lp),
      .fallo_init(fallo_init), .estado_D0(estado_D0),
      .lp_preparada(lp_preparada), .lp_p(lp_p), .lp_n(lp_n),
      .lp_oe(lp_oe), .hs_oen(hs_oen)
  );

  // Modelo de OEN activo bajo. No sustituye una simulación de primitivas Gowin.
  genvar lane;
  generate
    for (lane = 0; lane < 3; lane = lane + 1) begin: pads
      wire oen = ~lp_oe[lane];
      assign pads_p[lane] = oen ? 1'bz : lp_p[lane];
      assign pads_n[lane] = oen ? 1'bz : lp_n[lane];
      assign pads_hs_p[lane] = hs_oen[lane] ? 1'bz : 1'b0;
      assign pads_hs_n[lane] = hs_oen[lane] ? 1'bz : 1'b1;
    end
  endgenerate

  task pos;
    begin @(posedge clk); #1; end
  endtask

  task aislado;
    begin
      if (lp_preparada !== 0 || lp_oe !== 0 ||
          lp_p !== 3'b111 || lp_n !== 3'b111 ||
          pads_p !== 3'bzzz || pads_n !== 3'bzzz)
        $fatal(1, "N=%0d: aislamiento incorrecto", N);
    end
  endtask

  task resetear;
    begin
      @(negedge clk); #1;
      rst = 1;
      preparar_lp = 0;
      fallo_init = 0;
      #1; aislado;
      pos;
      @(negedge clk); #1;
      if (dut.w_tiempo !== 0) $fatal(1, "Contador no reseteado");
      rst = 0;
      #1; aislado;
    end
  endtask

  // Deja el DUT en AISLADO / PRECARGAR / ESTABILIZAR / LISTO.
  task ir_fase(input integer destino);
    begin
      resetear;
      if (destino > 0) begin
        preparar_lp = 1;
        pos;
        if (dut.ctrl.state !== 3'd1) $fatal(1, "Falta PRECARGAR");
        aislado;
      end
      if (destino > 1) begin
        pos;
        if (dut.ctrl.state !== 3'd2) $fatal(1, "Falta ESTABILIZAR");
      end
      if (destino > 2) begin
        repeat (N) pos;
        if (!lp_preparada) $fatal(1, "Falta LISTO");
      end
    end
  endtask

  initial begin
    // Preparación exacta: precarga un ciclo y LP-11 durante N ciclos completos.
    resetear;
    repeat (3) begin pos; aislado; end
    preparar_lp = 1;
    pos;
    aislado;
    pos;
    inicio = $time;
    if (lp_oe !== 3'b111 || lp_preparada !== 0 ||
        pads_p !== 3'b111 || pads_n !== 3'b111)
      $fatal(1, "Inicio de estabilización incorrecto");
    for (i = 1; i <= N; i = i + 1) begin
      @(negedge clk); #1;
      if (dut.w_tiempo !== i || lp_preparada !== 0)
        $fatal(1, "Contador/flag anticipado, i=%0d", i);
      pos;
      if (i < N && lp_preparada !== 0) $fatal(1, "LISTO anticipado");
    end
    if (!lp_preparada || $time - inicio != N * 25)
      $fatal(1, "Intervalo distinto de N ciclos");

    // Sin registro en D0: cambios entre flancos llegan al pad.
    for (i = 0; i < 4; i = i + 1) begin
      #2; estado_D0 = i; #1;
      if (pads_p !== {2'b11, estado_D0[1]} ||
          pads_n !== {2'b11, estado_D0[0]})
        $fatal(1, "Latencia o inversión P/N");
    end
    repeat (N + 3) pos;
    if (!lp_preparada || dut.w_tiempo !== N)
      $fatal(1, "Petición mantenida reinicia o desborda contador");

    for (fase = 0; fase < 4; fase = fase + 1) begin
      ir_fase(fase);
      #2; rst = 1; #1; aislado;
      pos;
      if (dut.ctrl.state !== 0) $fatal(1, "Reset no lleva a AISLADO");

      ir_fase(fase);
      #2; preparar_lp = 0; #1; aislado;
      pos;
      if (dut.ctrl.state !== 0) $fatal(1, "Retirada no lleva a AISLADO");
      ir_fase(3); // Retirar petición permite una nueva preparación completa.

      ir_fase(fase);
      #2; fallo_init = 1; preparar_lp = 0; #1; aislado;
      pos;
      if (dut.ctrl.state !== 4) $fatal(1, "Fallo sin prioridad");
      fallo_init = 0;
      preparar_lp = 1;
      repeat (N + 4) begin pos; aislado; end
      if (dut.ctrl.state !== 4) $fatal(1, "Fallo no enclavado");
      resetear;
    end

    // Los tres códigos no válidos inhiben antes del posedge y enclavan FALLO.
    for (codigo = 5; codigo < 8; codigo = codigo + 1) begin
      ir_fase(3);
      #2;
      case (codigo)
        5: force dut.ctrl.state = 3'd5;
        6: force dut.ctrl.state = 3'd6;
        7: force dut.ctrl.state = 3'd7;
      endcase
      #1; aislado;
      release dut.ctrl.state;
      pos;
      if (dut.ctrl.state !== 4) $fatal(1, "Estado inválido no enclava FALLO");
      aislado;
    end

    // Reset gana incluso con fallo activo.
    fallo_init = 1;
    rst = 1;
    pos;
    if (dut.ctrl.state !== 0) $fatal(1, "Reset sin prioridad sobre fallo");
    aislado;
    $display("PASS motor_phy N=%0d", N);
    $finish;
  end

  always @(negedge clk) begin
    #2;
    if (hs_oen !== 3'b111 || pads_hs_p !== 3'bzzz || pads_hs_n !== 3'bzzz)
      $fatal(1, "HS habilitado");
  end

  initial begin
    #100000;
    $fatal(1, "Timeout");
  end
endmodule
