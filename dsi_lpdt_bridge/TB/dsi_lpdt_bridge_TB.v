`timescale 1ns / 1ps

module dsi_lpdt_bridge_TB;
  reg clk = 0;
  always #12.5 clk = ~clk;
  reg rst = 1;
  reg permiso = 0;
  reg raw_mode = 1;
  reg [7:0] raw_data = 0;
  reg raw_valid = 0;
  reg raw_last = 0;
  reg cmd_valid = 0;
  reg [7:0] cmd_opcode = 0;
  reg cmd_has_param = 0;
  reg [7:0] cmd_param = 0;
  wire cmd_ready;
  wire [7:0] packet_data;
  wire packet_valid, packet_last, packet_ready, packet_done;
  wire [7:0] byte_data = raw_mode ? raw_data : packet_data;
  wire byte_valid = raw_mode ? raw_valid : packet_valid;
  wire byte_last = raw_mode ? raw_last : packet_last;
  wire byte_ready, busy, tx_done, packet_error, lp_req;
  wire [1:0] lp;

  assign packet_ready = !raw_mode && byte_ready;

  dsi_lp_packet_tx packetizer (
      .clk(clk), .rst(rst), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
      .cmd_opcode(cmd_opcode), .cmd_has_param(cmd_has_param), .cmd_param(cmd_param),
      .tx_byte_data(packet_data), .tx_byte_valid(packet_valid),
      .tx_byte_last(packet_last), .tx_byte_ready(packet_ready),
      .busy(), .packet_done(packet_done)
  );

  dsi_lpdt_bridge dut (
      .clk(clk), .rst(rst), .tx_byte_data(byte_data),
      .tx_byte_valid(byte_valid), .tx_byte_last(byte_last),
      .tx_byte_ready(byte_ready), .permiso_arranque(permiso),
      .lp_req(lp_req), .busy(busy), .tx_done(tx_done),
      .packet_error(packet_error), .estado_D0(lp)
  );

  // Vector esperado, byte inicial en los bits bajos. No se consulta el DUT.
  reg [31:0] expected_packet = 0;
  integer frames = 0;
  integer completions = 0;
  integer errors = 0;
  integer transfers = 0;
  integer monitor_aborts = 0;
  reg previous_done = 0;

  // Monitor por tramos: reconstruye Escape, cuarenta bits y Escape Exit.
  // No lee contadores, posiciones ni señales internas de ninguno de los RTL.
  reg [1:0] previous_lp = 2'b11;
  reg [1:0] runs [0:84];
  integer run_count = 0;
  integer run_cycles = 0;
  integer bit_number;
  reg [39:0] decoded;

  always @(negedge clk) begin
    #1;
    if (rst) begin
      if (lp !== 2'b11) $fatal(1, "D0 no vuelve a LP-11 durante reset");
      if (run_count != 0) monitor_aborts = monitor_aborts + 1;
      previous_lp = 2'b11;
      run_count = 0;
      run_cycles = 0;
    end else if (lp === previous_lp) begin
      run_cycles = run_cycles + 1;
    end else begin
      if (previous_lp != 2'b11 && run_cycles != 4)
        $fatal(1, "Fase LP-%02b dura %0d ciclos, esperaba 4", previous_lp, run_cycles);
      if (lp == 2'b11) begin
        if (run_count != 85)
          $fatal(1, "Numero de fases incorrecto: %0d", run_count);
        if (runs[0] !== 2'b10 || runs[1] !== 2'b00 ||
            runs[2] !== 2'b01 || runs[3] !== 2'b00 || runs[84] !== 2'b10)
          $fatal(1, "Entrada o salida Escape incorrecta");
        decoded = 0;
        for (bit_number = 0; bit_number < 40; bit_number = bit_number + 1) begin
          if ((runs[4+2*bit_number] !== 2'b01 && runs[4+2*bit_number] !== 2'b10) ||
              runs[5+2*bit_number] !== 2'b00)
            $fatal(1, "Mark/Space incorrecto, bit %0d", bit_number);
          decoded[bit_number] = (runs[4+2*bit_number] == 2'b10);
        end
        if (decoded !== {expected_packet, 8'h87})
          $fatal(1, "Bytes LPDT incorrectos: %010h != %010h", decoded,
                 {expected_packet, 8'h87});
        frames = frames + 1;
        run_count = 0;
      end else begin
        if (run_count >= 85) $fatal(1, "Demasiadas fases antes de LP-11");
        runs[run_count] = lp;
        run_count = run_count + 1;
      end
      previous_lp = lp;
      run_cycles = 1;
    end
  end

  always @(posedge clk) begin
    if (!rst && byte_valid && byte_ready) transfers = transfers + 1;
    if (rst && (byte_ready !== 0 || lp_req !== 0))
      $fatal(1, "ready o lp_req activo durante reset");
    #1;
    if (rst) begin
      if (busy !== 0 || tx_done !== 0 || packet_error !== 0)
        $fatal(1, "Reset no limpia estado y pulsos");
    end else begin
      if (tx_done) begin
        if (previous_done || busy !== 0 || byte_ready !== 1 || lp !== 2'b11 ||
            run_count != 0 || frames <= completions)
          $fatal(1, "Fin incorrecto o antes de completar LPDT");
        completions = completions + 1;
      end
      if (packet_error) begin
        if (tx_done || lp !== 2'b11)
          $fatal(1, "Error incorrecto o paquete invalido transmitido");
        errors = errors + 1;
      end
    end
    previous_done = tx_done;
  end

  task tick;
    begin @(posedge clk); #2; end
  endtask

  // Cambiar entradas después del muestreo del monitor del flanco descendente.
  task drive_time;
    begin @(negedge clk); #2; end
  endtask

  task reset_all;
    integer saved_completions;
    integer saved_errors;
    begin
      saved_completions = completions;
      saved_errors = errors;
      drive_time;
      rst = 1;
      raw_valid = 0;
      cmd_valid = 0;
      permiso = 0;
      repeat (3) tick;
      drive_time;
      rst = 0;
      repeat (3) tick;
      if (busy !== 0 || byte_ready !== 1 || lp !== 2'b11 ||
          completions != saved_completions || errors != saved_errors)
        $fatal(1, "Reset produce un fin/error o no permite recuperacion");
    end
  endtask

  task send_byte;
    input [7:0] data_value;
    input last_value;
    input integer gap;
    begin
      repeat (gap) tick;
      drive_time;
      raw_data = data_value;
      raw_last = last_value;
      raw_valid = 1;
      @(posedge clk);
      while (byte_ready !== 1) @(posedge clk);
      #2;
      drive_time;
      raw_valid = 0;
      // Cambiar datos sin valid no debe alterar la copia activa.
      raw_data = ~data_value;
      raw_last = ~last_value;
    end
  endtask

  task send_four;
    input [31:0] value;
    integer n;
    begin
      for (n = 0; n < 4; n = n + 1) begin
        send_byte(value[8*n +: 8], n == 3, n+1);
        if (n < 3 && (busy !== 1 || byte_ready !== 1 || lp !== 2'b11 || tx_done || lp_req))
          $fatal(1, "No conserva la captura parcial o arranca antes del cuarto byte");
      end
    end
  endtask

  task wait_done;
    integer limit;
    begin
      limit = 0;
      tick;
      while (!tx_done && limit < 450) begin
        tick;
        limit = limit + 1;
      end
      if (!tx_done) $fatal(1, "Timeout esperando fin LPDT");
    end
  endtask

  task wait_start;
    integer limit;
    begin
      limit = 0;
      while (lp == 2'b11 && limit < 30) begin
        tick;
        limit = limit + 1;
      end
      if (lp == 2'b11) $fatal(1, "Timeout esperando inicio LPDT");
    end
  endtask

  task check_idle;
    integer saved_frames;
    integer saved_completions;
    begin
      saved_frames = frames;
      saved_completions = completions;
      repeat (16) begin
        tick;
        if (lp !== 2'b11 || busy !== 0 || byte_ready !== 1 || tx_done !== 0 ||
            frames != saved_frames || completions != saved_completions)
          $fatal(1, "No permanece en reposo sin duplicar el envio");
      end
    end
  endtask

  task recovery_packet;
    integer saved_frames;
    integer saved_completions;
    begin
      saved_frames = frames;
      saved_completions = completions;
      expected_packet = 32'h10000105;
      send_four(expected_packet);
      drive_time;
      permiso = 1;
      wait_done;
      if (frames != saved_frames+1 || completions != saved_completions+1)
        $fatal(1, "Recuperacion no transmite exactamente un paquete");
      check_idle;
    end
  endtask

  task send_command;
    input [7:0] opcode;
    input has_param;
    input [7:0] param;
    begin
      drive_time;
      cmd_opcode = opcode;
      cmd_has_param = has_param;
      cmd_param = param;
      cmd_valid = 1;
      @(posedge clk);
      while (cmd_ready !== 1) @(posedge clk);
      #2;
      drive_time;
      cmd_valid = 0;
      cmd_opcode = ~opcode;
      cmd_has_param = ~has_param;
      cmd_param = ~param;
    end
  endtask

  integer n, j, saved_errors, saved_frames, saved_transfers;
  reg [7:0] held_data;
  reg held_last;
  string vcd_path;

  initial begin
    if ($value$plusargs("vcd=%s", vcd_path)) begin
      $dumpfile(vcd_path);
      $dumpvars(0, dsi_lpdt_bridge_TB);
    end
    reset_all;

    // Pausas de entrada, permiso demorado y siguiente byte pendiente.
    expected_packet = 32'h10000105;
    send_four(expected_packet);
    drive_time;
    raw_valid = 1;
    raw_data = 8'hff;
    raw_last = 1;
    saved_transfers = transfers;
    repeat (20) begin
      tick;
      if (!busy || byte_ready || lp !== 2'b11 || tx_done || !lp_req)
        $fatal(1, "Arranca sin permiso o acepta datos con el almacen lleno");
    end
    drive_time;
    permiso = 1;
    wait_start;
    drive_time;
    permiso = 0;  // Una vez aceptado, retirar permiso no interrumpe LPDT.
    while (!tx_done) begin
      tick;
      if (!tx_done && (!busy || byte_ready || lp_req))
        $fatal(1, "Pierde busy/backpressure durante transmision");
    end
    if (transfers != saved_transfers || frames != 1 || completions != 1)
      $fatal(1, "Sobrescritura del paquete o fin duplicado");
    drive_time;
    raw_valid = 0;
    check_idle;

    // El puente no interpreta el contenido: conserva tambien bytes arbitrarios.
    expected_packet = 32'haa55ff00;
    drive_time;
    permiso = 1;
    send_four(expected_packet);
    wait_done;
    check_idle;

    // Generador real: el segundo comando queda detenido al ofrecer su byte 0.
    reset_all;
    drive_time;
    raw_mode = 0;
    permiso = 1;
    expected_packet = 32'h36001105;
    send_command(8'h11, 0, 8'hff);
    send_command(8'h3a, 1, 8'h55);
    tick;
    held_data = packet_data;
    held_last = packet_last;
    repeat (12) begin
      tick;
      if (!packet_valid || packet_ready || packet_data !== held_data ||
          packet_last !== held_last || tx_done)
        $fatal(1, "El comando pendiente no conserva el byte con ready=0");
    end
    wait_done;
    expected_packet = 32'h02553a15;
    wait_done;
    check_idle;
    expected_packet = 32'h1c002905;
    send_command(8'h29, 0, 0);
    wait_done;
    check_idle;

    reset_all;
    drive_time;
    raw_mode = 1;
    permiso = 1;
    // last temprano en cada posicion invalida, y longitudes mayores que cuatro.
    for (n = 1; n <= 7; n = n + 1) begin
      if (n != 4) begin
        saved_errors = errors;
        saved_frames = frames;
        for (j = 0; j < n; j = j + 1) send_byte(j, j == n-1, j % 3);
        if (errors != saved_errors+1 || frames != saved_frames)
          $fatal(1, "Longitud %0d no produce exactamente un rechazo", n);
        check_idle;
        recovery_packet;
      end
    end

    // Reset con cero, uno, dos y tres bytes capturados.
    for (n = 0; n < 4; n = n + 1) begin
      reset_all;
      for (j = 0; j < n; j = j + 1) send_byte(8'haa, 0, 1);
      reset_all;
      recovery_packet;
    end

    // Reset esperando permiso, sin producir una transmision tardia.
    reset_all;
    send_four(32'h10000105);
    repeat (8) tick;
    reset_all;
    recovery_packet;

    // Reset en descarte, incluso si nunca se recibio last.
    reset_all;
    for (j = 0; j < 6; j = j + 1) send_byte(j, 0, 0);
    if (!busy || !byte_ready) $fatal(1, "No permanece descartando hasta last");
    reset_all;
    recovery_packet;

    // Reset en entrada Escape, selector, distintos bytes y salida de Escape.
    for (n = 0; n < 7; n = n + 1) begin
      reset_all;
      expected_packet = 32'h10000105;
      send_four(expected_packet);
      drive_time;
      permiso = 1;
      wait_start;
      case (n)
        0: repeat (1) tick;
        1: repeat (10) tick;
        2: repeat (20) tick;
        3: repeat (100) tick;
        4: repeat (200) tick;
        5: repeat (300) tick;
        6: repeat (336) tick;
      endcase
      reset_all;
      recovery_packet;
    end

    // Reset durante el pulso de fin y recuperacion posterior.
    expected_packet = 32'h10000105;
    send_four(expected_packet);
    wait_done;
    reset_all;
    recovery_packet;
    if (errors != 7 || monitor_aborts != 7 || frames != completions)
      $fatal(1, "Cobertura incorrecta: errores=%0d abortos=%0d frames=%0d fin=%0d",
             errors, monitor_aborts, frames, completions);
    $display("PASS dsi_lpdt_bridge: %0d paquetes LPDT, %0d rechazos, %0d abortos en D0; pausas, permiso, reset y generador real",
             frames, errors, monitor_aborts);
    $finish;
  end

  initial begin
    #2000000;
    $fatal(1, "Timeout global del testbench");
  end
endmodule
