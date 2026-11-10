`timescale 1ns / 1ps

module dphy_mode_edges_TB;
  reg clk = 0;
  always #12.5 clk = ~clk;
  reg rst = 1;
  reg lp_req = 0, lp_done = 0, hs_req = 0, hs_done = 0;
  reg hs_error = 0, hs_data_ready = 1, pll_locked = 1;
  reg clk_prepared = 0, data_prepared = 0, data_stopped = 0, clk_stopped = 0;
  reg stop_ready = 1, clear_error = 0;
  wire lp_req_ready, hs_req_ready, lp_grant, hs_grant, lp_complete, hs_complete;
  wire clk_start_req, data_start_req, data_stop_req, clk_stop_req;
  wire busy, error, phy_abort;
  wire [1:0] error_code;
  wire [5:0] controls = {lp_grant, hs_grant, clk_start_req,
                         data_start_req, data_stop_req, clk_stop_req};
  dphy_mode_ctrl dut (
      .clk(clk), .rst(rst), .lp_req(lp_req), .lp_req_ready(lp_req_ready),
      .lp_done(lp_done), .lp_grant(lp_grant), .lp_complete(lp_complete),
      .hs_req(hs_req), .hs_req_ready(hs_req_ready), .hs_done(hs_done),
      .hs_error(hs_error), .hs_data_ready(hs_data_ready), .pll_locked(pll_locked),
      .hs_grant(hs_grant), .hs_complete(hs_complete),
      .clk_start_req(clk_start_req), .clk_prepared(clk_prepared),
      .data_start_req(data_start_req), .data_prepared(data_prepared),
      .data_stop_req(data_stop_req), .data_stopped(data_stopped),
      .clk_stop_req(clk_stop_req), .clk_stopped(clk_stopped), .stop_ready(stop_ready),
      .clear_error(clear_error), .busy(busy), .error(error),
      .error_code(error_code), .phy_abort(phy_abort)
  );
  task rise;
    begin @(posedge clk); #1; end
  endtask
  task fall;
    begin @(negedge clk); #1; end
  endtask
  task reset_all;
    begin
      @(negedge clk); #2;
      rst = 1; lp_req = 0; hs_req = 0; lp_done = 0; hs_done = 0;
      hs_error = 0; hs_data_ready = 1; pll_locked = 1;
      clk_prepared = 0; data_prepared = 0; data_stopped = 0; clk_stopped = 0;
      stop_ready = 1; clear_error = 0;
      rise; fall; rise; fall;
      #1; rst = 0;
      rise; fall;
      if (busy || error || error_code || lp_complete || hs_complete || controls)
        $fatal(1, "Reset no deja estado limpio");
    end
  endtask
  task start_hs;
    begin
      #1; hs_req = 1;
      rise;
      if (controls !== 6'b001000) $fatal(1, "No reserva HS en posedge");
      fall;
      #1; hs_req = 0;
    end
  endtask
  task pending_reset;
    begin
      #1; rst = 1;
      #1;
      if (controls || lp_req_ready || hs_req_ready || !phy_abort)
        $fatal(1, "Reset no bloquea combinacionalmente");
      fall;
      if (error_code || lp_complete || hs_complete)
        $fatal(1, "Reset no anula accion pendiente en negedge");
      rise; fall;
      #1; rst = 0; lp_req = 0; hs_req = 0; lp_done = 0;
      pll_locked = 1; hs_error = 0;
      rise; fall;
      if (busy || error || controls || lp_complete || hs_complete)
        $fatal(1, "Una accion vieja reaparece despues de reset");
    end
  endtask
  task release_lp;
    begin
      #1; lp_done = 1;
      rise;
      if (lp_grant || !busy) $fatal(1, "No retira grant al observar lp_done");
      #1; lp_done = 0;
      fall;
      rise;
      if (busy || lp_complete) $fatal(1, "El fin cambio antes del negedge de liberacion");
    end
  endtask
  integer cases = 0, kind;
  reg [3:0] injected_state;
  string vcd_path;
  initial begin
    if ($value$plusargs("vcd=%s", vcd_path)) begin
      $dumpfile(vcd_path); $dumpvars(0, dphy_mode_edges_TB);
    end
    reset_all;
    // Aceptacion y preferencia sobreviven al cambio de estado y de req.
    #1; lp_req = 1; hs_req = 1;
    rise;
    if (!lp_grant) $fatal(1, "No respeta preferencia LP inicial");
    #1; lp_req = 0; hs_req = 0;
    fall;
    #1; lp_req = 1; hs_req = 1;
    release_lp;
    #1; stop_ready = 0;
    fall;
    if (!lp_complete || busy) $fatal(1, "Se perdio el evento de fin al entrar en IDLE");
    rise;
    if (!lp_complete) $fatal(1, "Pulso de fin menor de un ciclo negedge-negedge");
    fall;
    if (lp_complete) $fatal(1, "Fin no se limpia en el siguiente negedge");
    #1; stop_ready = 1;
    rise;
    if (!clk_start_req || lp_grant) $fatal(1, "No conserva preferencia HS ni rearme temprano");
    fall;
    cases = cases+1;

    // Causa capturada en posedge: no depender de PLL/error vivos en negedge.
    for (kind = 1; kind <= 2; kind = kind+1) begin
      reset_all;
      start_hs;
      #1; hs_error = 1;
      if (kind == 1) pll_locked = 0;
      #1;
      if (controls || !phy_abort || error) $fatal(1, "Proteccion combinacional de HS incorrecta");
      rise;
      if (!error || error_code !== 0) $fatal(1, "Causa cambio en posedge");
      #1; pll_locked = 1; hs_error = 0;
      fall;
      if (error_code !== kind[1:0]) $fatal(1, "Se perdio la causa entre posedge y negedge");
      rise; fall;
      if (error_code !== kind[1:0]) $fatal(1, "Causa no permanece hasta limpieza");
      #1; clear_error = 1;
      rise;
      if (error || error_code !== kind[1:0]) $fatal(1, "No separa liberacion de limpieza del datapath");
      #1; clear_error = 0;
      fall;
      if (error_code || busy) $fatal(1, "Se perdio la accion CLEAR tras volver a IDLE");
      cases = cases+1;
    end

    // Una perturbacion entre flancos bloquea salida, sin capturar un fallo
    // que no estaba presente en posedge. No pretende modelar CDC.
    reset_all;
    start_hs;
    rise;
    #1; hs_error = 1;
    #1;
    if (controls || !phy_abort) $fatal(1, "Proteccion espera indebidamente otro reloj");
    fall;
    if (error || error_code) $fatal(1, "UC capturo fallo en negedge");
    #1; hs_error = 0;
    rise; fall;
    if (error || error_code || !clk_start_req) $fatal(1, "Registra un fallo ausente en posedge");
    cases = cases+1;

    // Reset entre decision y aplicacion: aceptacion, fin y causa pendientes.
    reset_all;
    #1; lp_req = 1;
    rise;
    pending_reset;
    cases = cases+1;
    reset_all;
    #1; lp_req = 1;
    rise; fall;
    release_lp;
    pending_reset;
    cases = cases+1;
    reset_all;
    start_hs;
    #1; hs_error = 1;
    rise;
    pending_reset;
    cases = cases+1;

    // Inyeccion exclusiva del test: los seis codigos no usados son
    // inalcanzables desde reset por entradas publicas.
    for (kind = 10; kind < 16; kind = kind+1) begin
      reset_all;
      injected_state = kind;
      #1; force dut.control.state = injected_state;
      #1; release dut.control.state;
      if (controls || lp_req_ready || hs_req_ready) $fatal(1, "Codigo invalido conduce el enlace");
      rise;
      if (!error || error_code !== 0) $fatal(1, "No registra FAULT o causa cambia en posedge");
      fall;
      if (error_code !== 2'd3) $fatal(1, "No captura causa 3 para codigo no usado");
      cases = cases+1;
    end
    if (cases != 13) $fatal(1, "Cobertura entre flancos incompleta");
    $display("PASS dphy_mode_edges: %0d casos; eventos retenidos, causa estable, reset pendiente y codigos 10..15", cases);
    $finish;
  end
  initial begin
    #100000;
    $fatal(1, "Timeout global dphy_mode_edges_TB");
  end
endmodule
