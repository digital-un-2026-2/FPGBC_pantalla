`timescale 1ns / 1ps

module dphy_mode_ctrl_TB;
  reg clk = 0;
  always #12.5 clk = ~clk;
  reg rst = 1;
  reg lp_req = 0, lp_done = 0, hs_req = 0, hs_done = 0;
  reg hs_error = 0, hs_data_ready = 1, pll_locked = 1;
  reg clk_prepared = 0, data_prepared = 0, data_stopped = 0, clk_stopped = 0;
  reg stop_ready = 1, clear_error = 0;
  wire lp_req_ready, hs_req_ready, lp_grant, hs_grant;
  wire lp_complete, hs_complete, busy, error, phy_abort;
  wire clk_start_req, data_start_req, data_stop_req, clk_stop_req;
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

  integer lp_accepted = 0, hs_accepted = 0;
  integer lp_finished = 0, hs_finished = 0, fault_cases = 0, reset_cases = 0;
  reg prev_lp_complete = 0, prev_hs_complete = 0;
  reg [6:0] datapath_before;
  reg [7:0] control_before;

  always @(posedge clk) begin
    datapath_before = {dut.datapath.r_lp, dut.datapath.r_hs, dut.datapath.pref,
                       error_code, lp_complete, hs_complete};
    if (!rst) begin
      if (lp_req && lp_req_ready) lp_accepted = lp_accepted+1;
      if (hs_req && hs_req_ready) hs_accepted = hs_accepted+1;
    end
    #1;
    if ({dut.datapath.r_lp, dut.datapath.r_hs, dut.datapath.pref,
         error_code, lp_complete, hs_complete} !== datapath_before)
      $fatal(1, "Un registro del datapath cambio en posedge");
    if (lp_req_ready && hs_req_ready) $fatal(1, "Dos reservas simultaneas");
    if (lp_grant && (hs_grant || clk_start_req || data_start_req || data_stop_req || clk_stop_req))
      $fatal(1, "LP y HS tienen propiedad simultanea");
    if ((data_start_req || data_stop_req || hs_grant) && !clk_start_req)
      $fatal(1, "Datos HS sin reloj preparado/activo");
    if (clk_stop_req && (clk_start_req || data_start_req || data_stop_req || hs_grant))
      $fatal(1, "Parada del reloj antes de liberar datos");
    if ((rst || error) && (controls !== 0 || lp_req_ready || hs_req_ready || !phy_abort))
      $fatal(1, "Reset/fallo conserva grants u ordenes");
  end

  // Los siete bits del datapath se observan tras negedge, antes de otra
  // posible aceptacion en posedge. El estado/accion de UC debe conservarse.
  always @(negedge clk) begin
    control_before = {dut.control.state, dut.control.action};
    #1;
    if ({dut.control.state, dut.control.action} !== control_before)
      $fatal(1, "La memoria de control cambio en negedge");
    if (rst && (error_code !== 0 || lp_complete !== 0 || hs_complete !== 0))
      $fatal(1, "Reset no limpia datapath en negedge");
    if (!rst) begin
      if (lp_complete) begin
        if (prev_lp_complete || hs_complete || busy || !stop_ready || error)
          $fatal(1, "Fin LP incorrecto");
        lp_finished = lp_finished+1;
      end
      if (hs_complete) begin
        if (prev_hs_complete || lp_complete || busy || !stop_ready || error)
          $fatal(1, "Fin HS incorrecto");
        hs_finished = hs_finished+1;
      end
    end
    prev_lp_complete = lp_complete;
    prev_hs_complete = hs_complete;
  end

  task drive;
    begin @(negedge clk); #2; end
  endtask
  task tick;
    // Una decision en posedge y su aplicacion al datapath en negedge.
    begin @(posedge clk); #2; @(negedge clk); #2; end
  endtask
  task expect_controls;
    input [5:0] value;
    begin
      if (controls !== value || !busy || error)
        $fatal(1, "Controles %06b != %06b, busy=%b error=%b", controls, value, busy, error);
    end
  endtask
  task reset_all;
    integer finished_before;
    begin
      finished_before = lp_finished+hs_finished;
      drive;
      rst = 1;
      lp_req = 0; hs_req = 0; lp_done = 0; hs_done = 0;
      hs_error = 0; hs_data_ready = 1; pll_locked = 1;
      clk_prepared = 0; data_prepared = 0; data_stopped = 0; clk_stopped = 0;
      stop_ready = 1; clear_error = 0;
      #1;
      if (controls !== 0 || !phy_abort || lp_req_ready || hs_req_ready)
        $fatal(1, "Reset no bloquea salidas antes del flanco");
      repeat (2) tick;
      if (busy || error_code || lp_complete || hs_complete)
        $fatal(1, "Reset no limpia estado");
      drive; rst = 0;
      tick;
      if (busy || error || phy_abort || finished_before != lp_finished+hs_finished)
        $fatal(1, "Reset genera finalizacion");
      reset_cases = reset_cases+1;
    end
  endtask
  task finish_lp;
    begin
      drive; lp_done = 1; stop_ready = 0;
      tick;
      expect_controls(0);
      drive; lp_done = 0;
      repeat (3) begin
        tick;
        expect_controls(0);
        if (lp_complete) $fatal(1, "Fin LP sin reposo confirmado");
      end
      drive; stop_ready = 1;
      tick;
      if (!lp_complete || busy) $fatal(1, "No finaliza LP tras reposo");
    end
  endtask
  // Llegar a cada fase HS usando solo puertos publicos y ACKs externos.
  task enter_hs_phase;
    input integer phase_number;
    begin
      drive; hs_req = 1;
      tick;
      expect_controls(6'b001000);
      drive; hs_req = 0; stop_ready = 0;
      if (phase_number >= 1) begin
        clk_prepared = 1;
        tick;
        expect_controls(6'b001100);
        drive;
      end
      if (phase_number >= 2) begin
        data_prepared = 1;
        tick;
        expect_controls(6'b011100);
        drive;
      end
      if (phase_number >= 3) begin
        hs_done = 1;
        tick;
        expect_controls(6'b001010);
        drive; hs_done = 0;
      end
      if (phase_number >= 4) begin
        data_stopped = 1;
        tick;
        expect_controls(6'b000001);
        drive;
      end
      if (phase_number >= 5) begin
        clk_stopped = 1;
        tick;
        expect_controls(0);
        drive;
      end
    end
  endtask
  task finish_hs;
    begin
      // Se llama desde preparacion del reloj; se demoran todos los ACKs.
      repeat (3) begin tick; expect_controls(6'b001000); end
      drive; clk_prepared = 1; stop_ready = 0;
      tick; expect_controls(6'b001100);
      repeat (3) begin tick; expect_controls(6'b001100); end
      drive; data_prepared = 1;
      tick; expect_controls(6'b011100);
      repeat (8) begin tick; expect_controls(6'b011100); end
      drive; hs_done = 1;
      tick; expect_controls(6'b001010);
      drive; hs_done = 0;
      repeat (3) begin tick; expect_controls(6'b001010); end
      drive; data_stopped = 1;
      tick; expect_controls(6'b000001);
      repeat (3) begin tick; expect_controls(6'b000001); end
      drive; clk_stopped = 1;
      tick; expect_controls(0);
      repeat (3) begin
        tick; expect_controls(0);
        if (hs_complete) $fatal(1, "Fin HS antes de confirmar reposo");
      end
      drive; stop_ready = 1;
      tick;
      if (!hs_complete || busy) $fatal(1, "No finaliza HS tras reposo");
    end
  endtask

  integer n, kind, accepted_before, finished_before;
  string vcd_path;
  initial begin
    if ($value$plusargs("vcd=%s", vcd_path)) begin
      $dumpfile(vcd_path); $dumpvars(0, dphy_mode_ctrl_TB);
    end
    reset_all;
    // No aceptar sin reposo; ignorar todos los ACK/done ajenos a la fase.
    drive;
    stop_ready = 0; lp_req = 1; hs_req = 1; lp_done = 1; hs_done = 1;
    clk_prepared = 1; data_prepared = 1; data_stopped = 1; clk_stopped = 1;
    repeat (4) begin
      tick;
      if (controls || lp_req_ready || hs_req_ready || busy || lp_complete || hs_complete)
        $fatal(1, "Acepta sin reposo o procesa ACK fuera de fase");
    end

    // Alternancia con ambos productores pendientes en cada arbitraje.
    reset_all;
    for (n = 0; n < 6; n = n+1) begin
      drive;
      lp_req = 1; hs_req = 1; stop_ready = 1;
      clk_prepared = 0; data_prepared = 0; data_stopped = 0; clk_stopped = 0;
      tick;
      if (n % 2 == 0) expect_controls(6'b100000);
      else expect_controls(6'b001000);
      drive; lp_req = 0; hs_req = 0;
      tick;
      drive; lp_req = 1; hs_req = 1;
      if (n % 2 == 0) finish_lp;
      else finish_hs;
    end

    // LP funciona con PLL no disponible o datos HS no disponibles.
    for (kind = 0; kind < 3; kind = kind+1) begin
      reset_all;
      drive; lp_req = 1; hs_req = 1;
      if (kind == 0) pll_locked = 0;
      if (kind == 1) hs_data_ready = 0;
      if (kind == 2) hs_error = 1;
      tick; expect_controls(6'b100000);
      finish_lp;
      repeat (4) begin
        tick;
        if (busy || controls || error || lp_req_ready || hs_req_ready)
          $fatal(1, "Duplica solicitud mantenida o acepta HS no elegible");
      end
    end

    // Perdida de disponibilidad antes de grant espera; durante transferencia
    // no se usa como ready ni se interrumpe por solicitudes LP.
    reset_all;
    enter_hs_phase(1);
    hs_data_ready = 0; data_prepared = 1; lp_req = 1;
    repeat (4) begin tick; expect_controls(6'b001100); end
    drive; hs_data_ready = 1;
    tick; expect_controls(6'b011100);
    drive; hs_data_ready = 0;
    repeat (6) begin tick; expect_controls(6'b011100); end

    // Reset en todas las fases HS y fallos de ambos tipos en esas fases.
    for (n = 0; n < 6; n = n+1) begin
      reset_all;
      enter_hs_phase(n);
      reset_all;
      for (kind = 1; kind <= 2; kind = kind+1) begin
        enter_hs_phase(n);
        finished_before = hs_finished;
        if (kind == 1) pll_locked = 0;
        else hs_error = 1;
        #1;
        if (controls !== 0 || !phy_abort) $fatal(1, "Fallo no retira salidas inmediatamente");
        tick;
        if (!error || error_code !== kind[1:0] || hs_complete || hs_finished != finished_before)
          $fatal(1, "Fallo no queda registrado sin exito");
        drive; pll_locked = 1; hs_error = 0; clear_error = 1; stop_ready = 0;
        repeat (3) begin
          tick;
          if (!error || !phy_abort) $fatal(1, "Limpia fallo sin reposo");
        end
        drive; stop_ready = 1;
        tick;
        if (error || busy || error_code || phy_abort) $fatal(1, "No recupera tras fallo");
        fault_cases = fault_cases+1;
        reset_all;
      end
    end

    // Una peticion HS mantenida no se reintenta automaticamente tras fallo.
    drive; hs_req = 1;
    tick; expect_controls(6'b001000);
    drive; pll_locked = 0;
    tick;
    drive; pll_locked = 1; clear_error = 1;
    tick;
    accepted_before = hs_accepted;
    repeat (4) tick;
    if (hs_accepted != accepted_before || busy) $fatal(1, "Reintenta HS sin rearme");
    drive; hs_req = 0; clear_error = 0;
    tick;
    enter_hs_phase(0);
    finish_hs;

    // Reset durante LP, espera de reposo LP y fallo persistente.
    reset_all;
    drive; lp_req = 1;
    tick; expect_controls(6'b100000);
    reset_all;
    drive; lp_req = 1;
    tick;
    drive; lp_done = 1; stop_ready = 0;
    tick; expect_controls(0);
    reset_all;
    enter_hs_phase(2);
    hs_error = 1;
    tick;
    reset_all;

    // Fin normal HS con solicitud mantenida; no duplicar al volver a reposo.
    drive; hs_req = 1;
    tick; expect_controls(6'b001000);
    finish_hs;
    accepted_before = hs_accepted;
    repeat (5) tick;
    if (hs_accepted != accepted_before || busy) $fatal(1, "Duplica HS tras fin normal");
    if (fault_cases != 12 || lp_finished != 6 || hs_finished != 5)
      $fatal(1, "Cobertura inesperada: LP=%0d HS=%0d fallos=%0d", lp_finished, hs_finished, fault_cases);
    $display("PASS dphy_mode_ctrl: LP=%0d HS=%0d completos, %0d fallos por fase, %0d resets; arbitraje, exclusividad y rearme",
             lp_finished, hs_finished, fault_cases, reset_cases);
    $finish;
  end
  initial begin
    #500000;
    $fatal(1, "Timeout global dphy_mode_ctrl_TB");
  end
endmodule
