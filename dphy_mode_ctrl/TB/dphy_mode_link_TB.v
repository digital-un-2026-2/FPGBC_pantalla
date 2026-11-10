`timescale 1ns / 1ps

module dphy_mode_link_TB;
  reg clk = 0;
  always #12.5 clk = ~clk;
  reg rst = 1;
  reg cmd_valid = 0, cmd_has_param = 0;
  reg [7:0] cmd_opcode = 0, cmd_param = 0;
  wire cmd_ready, byte_valid, byte_last, byte_ready;
  wire [7:0] byte_data;
  wire lp_req, lp_done, lp_grant, bridge_busy, packet_error;
  wire [1:0] lp;
  reg hs_req = 0;
  reg hs_done = 0;
  wire hs_req_ready, hs_grant, lp_complete, hs_complete;
  wire clk_start_req, data_start_req, data_stop_req, clk_stop_req;
  wire mode_busy, error, phy_abort;
  wire [1:0] error_code;

  reg clk_prepared = 0, data_prepared = 0, data_stopped = 0, clk_stopped = 0;
  reg mock_clk_active = 0, mock_data_active = 0;
  integer clk_prepare_count = 0, data_prepare_count = 0;
  integer data_stop_count = 0, clk_stop_count = 0, settle_count = 0;
  integer transfer_count = 0;
  integer scenario = 0;
  wire stop_ready = !mock_clk_active && !mock_data_active &&
                    (settle_count == 0) && (lp == 2'b11);

  dsi_lp_packet_tx packetizer (
      .clk(clk), .rst(rst), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
      .cmd_opcode(cmd_opcode), .cmd_has_param(cmd_has_param), .cmd_param(cmd_param),
      .tx_byte_data(byte_data), .tx_byte_valid(byte_valid),
      .tx_byte_last(byte_last), .tx_byte_ready(byte_ready), .busy(), .packet_done()
  );
  dsi_lpdt_bridge bridge (
      .clk(clk), .rst(rst), .tx_byte_data(byte_data), .tx_byte_valid(byte_valid),
      .tx_byte_last(byte_last), .tx_byte_ready(byte_ready), .permiso_arranque(lp_grant),
      .lp_req(lp_req), .busy(bridge_busy), .tx_done(lp_done),
      .packet_error(packet_error), .estado_D0(lp)
  );
  dphy_mode_ctrl dut (
      .clk(clk), .rst(rst), .lp_req(lp_req), .lp_req_ready(),
      .lp_done(lp_done), .lp_grant(lp_grant), .lp_complete(lp_complete),
      .hs_req(hs_req), .hs_req_ready(hs_req_ready), .hs_done(hs_done),
      .hs_error(1'b0), .hs_data_ready(1'b1), .pll_locked(1'b1),
      .hs_grant(hs_grant), .hs_complete(hs_complete),
      .clk_start_req(clk_start_req), .clk_prepared(clk_prepared),
      .data_start_req(data_start_req), .data_prepared(data_prepared),
      .data_stop_req(data_stop_req), .data_stopped(data_stopped),
      .clk_stop_req(clk_stop_req), .clk_stopped(clk_stopped), .stop_ready(stop_ready),
      .clear_error(1'b0), .busy(mode_busy), .error(error),
      .error_code(error_code), .phy_abort(phy_abort)
  );

  // Modelo funcional independiente. Latencias en ciclos elegidas solo para
  // ejercicio de handshake: no representan parametros D-PHY ni serializacion.
  always @(posedge clk) begin
    hs_done <= 0;
    if (rst || phy_abort) begin
      mock_clk_active <= 0; mock_data_active <= 0;
      clk_prepared <= 0; data_prepared <= 0; data_stopped <= 0; clk_stopped <= 0;
      clk_prepare_count <= 0; data_prepare_count <= 0;
      data_stop_count <= 0; clk_stop_count <= 0; settle_count <= 0;
      transfer_count <= 0;
    end else begin
      if (settle_count > 0) settle_count <= settle_count-1;
      if (clk_start_req && !mock_clk_active) begin
        mock_clk_active <= 1;
        clk_prepared <= 0; clk_stopped <= 0;
        clk_prepare_count <= 0; clk_stop_count <= 0;
      end else if (clk_start_req && !clk_prepared) begin
        if (clk_prepare_count == 3+scenario) clk_prepared <= 1;
        else clk_prepare_count <= clk_prepare_count+1;
      end
      if (data_start_req && !mock_data_active) begin
        if (!clk_prepared) $fatal(1, "Modelo recibe inicio de datos sin reloj preparado");
        mock_data_active <= 1;
        data_prepared <= 0; data_stopped <= 0;
        data_prepare_count <= 0; data_stop_count <= 0;
      end else if (data_start_req && !data_prepared) begin
        if (data_prepare_count == 2+scenario) data_prepared <= 1;
        else data_prepare_count <= data_prepare_count+1;
      end
      if (hs_grant) begin
        if (!clk_prepared || !data_prepared) $fatal(1, "Grant HS antes de preparar PHY");
        if (transfer_count == 12+scenario) hs_done <= 1;
        transfer_count <= transfer_count+1;
      end else transfer_count <= 0;
      if (data_stop_req && !data_stopped) begin
        if (data_stop_count == 2+scenario) begin
          mock_data_active <= 0; data_prepared <= 0; data_stopped <= 1;
        end else data_stop_count <= data_stop_count+1;
      end
      if (clk_stop_req && !clk_stopped) begin
        if (mock_data_active) $fatal(1, "Modelo recibe parada del reloj antes de los datos");
        if (clk_stop_count == 3+scenario) begin
          mock_clk_active <= 0; clk_prepared <= 0; clk_stopped <= 1;
          settle_count <= 4+scenario;
        end else clk_stop_count <= clk_stop_count+1;
      end
    end
  end

  integer lp_finished = 0, hs_finished = 0, hs_accepted = 0;
  integer decoded_frames = 0, pending_during_hs = 0, pending_during_lp = 0;
  reg [31:0] expected_packet = 0;
  reg [1:0] previous_lp = 2'b11;
  reg [1:0] runs [0:84];
  integer run_count = 0, run_cycles = 0, bit_index;
  reg [39:0] decoded;

  always @(posedge clk) begin
    if (!rst && hs_req && hs_req_ready) hs_accepted = hs_accepted+1;
    #1;
    if (!rst) begin
      if (error || packet_error || error_code) $fatal(1, "Error en prueba integrada");
      if (lp_complete) begin
        if (lp !== 2'b11 || decoded_frames != lp_finished+1 || !stop_ready)
          $fatal(1, "Fin LP sin paquete reconstruido o sin reposo");
        lp_finished = lp_finished+1;
      end
      if (hs_complete) begin
        if (!stop_ready || mock_clk_active || mock_data_active)
          $fatal(1, "Fin HS antes de parar PHY");
        hs_finished = hs_finished+1;
      end
      if (lp_req && mock_clk_active) pending_during_hs = pending_during_hs+1;
      if (hs_req && lp_grant) pending_during_lp = pending_during_lp+1;
    end
  end

  // Reconstruir la ruta LP real desde estados de D0, sin inspeccionar el RTL.
  always @(negedge clk) begin
    #1;
    if (!rst && ((lp_grant && (mock_clk_active || mock_data_active || hs_grant)) ||
        (lp !== 2'b11 && (mock_clk_active || mock_data_active || hs_grant))))
      $fatal(1, "Solapamiento entre LPDT real y PHY HS de prueba");
    if (rst) begin
      previous_lp = 2'b11; run_count = 0; run_cycles = 0;
    end else if (lp === previous_lp) run_cycles = run_cycles+1;
    else begin
      if (previous_lp != 2'b11 && run_cycles != 4) $fatal(1, "Duracion LP incorrecta");
      if (lp == 2'b11) begin
        if (run_count != 85 || runs[0] !== 2'b10 || runs[1] !== 0 ||
            runs[2] !== 2'b01 || runs[3] !== 0 || runs[84] !== 2'b10)
          $fatal(1, "Escape LPDT incorrecto");
        decoded = 0;
        for (bit_index = 0; bit_index < 40; bit_index = bit_index+1) begin
          if ((runs[4+2*bit_index] !== 2'b01 && runs[4+2*bit_index] !== 2'b10) ||
              runs[5+2*bit_index] !== 0) $fatal(1, "Mark/Space incorrecto");
          decoded[bit_index] = (runs[4+2*bit_index] == 2'b10);
        end
        if (decoded !== {expected_packet, 8'h87})
          $fatal(1, "LPDT integrado: %010h != %010h", decoded, {expected_packet, 8'h87});
        decoded_frames = decoded_frames+1;
        run_count = 0;
      end else begin
        if (run_count >= 85) $fatal(1, "LPDT integrado tiene fases extra");
        runs[run_count] = lp;
        run_count = run_count+1;
      end
      previous_lp = lp;
      run_cycles = 1;
    end
  end

  task drive;
    begin @(negedge clk); #2; end
  endtask
  task tick;
    begin @(posedge clk); #2; end
  endtask
  task command;
    input [7:0] opcode;
    input has_param;
    input [7:0] param;
    begin
      drive;
      cmd_opcode = opcode; cmd_has_param = has_param; cmd_param = param; cmd_valid = 1;
      @(posedge clk);
      while (!cmd_ready) @(posedge clk);
      #2;
      drive;
      cmd_valid = 0; cmd_opcode = ~opcode; cmd_param = ~param;
    end
  endtask
  task wait_finished;
    input integer lp_target;
    input integer hs_target;
    integer timeout;
    begin
      timeout = 0;
      while ((lp_finished < lp_target || hs_finished < hs_target) && timeout < 600) begin
        tick; timeout = timeout+1;
      end
      if (lp_finished != lp_target || hs_finished != hs_target)
        $fatal(1, "Timeout o fin duplicado en integracion");
      repeat (3) tick;
      if (mode_busy || bridge_busy || !stop_ready)
        $fatal(1, "No libera enlace despues de ambas operaciones");
    end
  endtask

  integer round_index, timeout, before_hs;
  string vcd_path;
  initial begin
    if ($value$plusargs("vcd=%s", vcd_path)) begin
      $dumpfile(vcd_path); $dumpvars(0, dphy_mode_link_TB);
    end
    repeat (3) tick;
    drive; rst = 0;
    repeat (3) tick;
    for (round_index = 0; round_index < 4; round_index = round_index+1) begin
      scenario = round_index;
      // Primero HS. LP puede formar su paquete pero no conducir D0.
      drive; hs_req = 1;
      @(posedge clk);
      while (!hs_req_ready) @(posedge clk);
      #2;
      drive; hs_req = 0;
      expected_packet = 32'h10000105;
      command(8'h01, 0, 8'hff);
      timeout = 0;
      while (!lp_req && timeout < 20) begin tick; timeout = timeout+1; end
      if (!lp_req || lp_grant || lp !== 2'b11 || !mock_clk_active)
        $fatal(1, "LP no espera la operacion HS previa");
      wait_finished(2*round_index+1, 2*round_index+1);

      // Primero LP. HS espera mientras el motor emite sus cuarenta bits.
      expected_packet = 32'h02553a15;
      command(8'h3a, 1, 8'h55);
      timeout = 0;
      while (!lp_grant && timeout < 30) begin tick; timeout = timeout+1; end
      if (!lp_grant) $fatal(1, "LP no consigue propiedad");
      before_hs = hs_accepted;
      drive; hs_req = 1;
      repeat (20) begin
        tick;
        if (hs_accepted != before_hs || !lp_grant || clk_start_req || hs_grant)
          $fatal(1, "HS interrumpe una operacion LP activa");
      end
      timeout = 0;
      while (hs_accepted == before_hs && timeout < 450) begin tick; timeout = timeout+1; end
      if (hs_accepted != before_hs+1) $fatal(1, "HS pendiente no consigue propiedad");
      drive; hs_req = 0;
      wait_finished(2*round_index+2, 2*round_index+2);
    end
    repeat (16) tick;
    if (decoded_frames != 8 || lp_finished != 8 || hs_finished != 8 || hs_accepted != 8 ||
        pending_during_hs == 0 || pending_during_lp == 0)
      $fatal(1, "Cobertura/duplicacion incorrecta en integracion");
    $display("PASS dphy_mode_link: %0d paquetes LPDT reconstruidos y %0d operaciones HS simuladas, cuatro latencias PHY, sin solapamiento",
             decoded_frames, hs_finished);
    $finish;
  end
  initial begin
    #500000;
    $fatal(1, "Timeout global dphy_mode_link_TB");
  end
endmodule
