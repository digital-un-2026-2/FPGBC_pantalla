`timescale 1ns / 1ps

module dsi_lp_packet_tx_TB;

  reg clk = 1'b0;
  always #12.5 clk = ~clk;

  reg rst = 1'b1;
  reg cmd_valid = 1'b0;
  reg [7:0] cmd_opcode = 8'h00;
  reg cmd_has_param = 1'b0;
  reg [7:0] cmd_param = 8'h00;
  reg tx_byte_ready = 1'b0;
  wire cmd_ready;
  wire [7:0] tx_byte_data;
  wire tx_byte_valid;
  wire tx_byte_last;
  wire busy;
  wire packet_done;

  dsi_lp_packet_tx dut (
      .clk(clk), .rst(rst),
      .cmd_valid(cmd_valid), .cmd_opcode(cmd_opcode),
      .cmd_has_param(cmd_has_param), .cmd_param(cmd_param),
      .cmd_ready(cmd_ready),
      .tx_byte_data(tx_byte_data), .tx_byte_valid(tx_byte_valid),
      .tx_byte_last(tx_byte_last), .tx_byte_ready(tx_byte_ready),
      .busy(busy), .packet_done(packet_done)
  );

  reg [23:0] ecc_header = 24'h000000;
  wire [7:0] ecc_result;
  packet_ecc ecc_probe (.header(ecc_header), .ecc(ecc_result));

  // Modelo externo: síndromes por bit, en lugar de las seis ecuaciones RTL.
  // Columnas de la matriz DSI, contrastadas con sun6i_dsi_ecc_array (Linux).
  function [7:0] reference_ecc;
    input [23:0] header;
    integer bit_index;
    reg [7:0] syndrome;
    begin
      reference_ecc = 8'h00;
      for (bit_index = 0; bit_index < 24; bit_index = bit_index + 1) begin
        case (bit_index)
          0: syndrome = 8'h07;  1: syndrome = 8'h0b;
          2: syndrome = 8'h0d;  3: syndrome = 8'h0e;
          4: syndrome = 8'h13;  5: syndrome = 8'h15;
          6: syndrome = 8'h16;  7: syndrome = 8'h19;
          8: syndrome = 8'h1a;  9: syndrome = 8'h1c;
          10: syndrome = 8'h23; 11: syndrome = 8'h25;
          12: syndrome = 8'h26; 13: syndrome = 8'h29;
          14: syndrome = 8'h2a; 15: syndrome = 8'h2c;
          16: syndrome = 8'h31; 17: syndrome = 8'h32;
          18: syndrome = 8'h34; 19: syndrome = 8'h38;
          20: syndrome = 8'h1f; 21: syndrome = 8'h2f;
          22: syndrome = 8'h37; 23: syndrome = 8'h3b;
          default: syndrome = 8'h00;
        endcase
        if (header[bit_index]) reference_ecc = reference_ecc ^ syndrome;
      end
    end
  endfunction

  function [31:0] reference_packet;
    input [7:0] opcode;
    input has_param;
    input [7:0] param;
    reg [23:0] header;
    begin
      if (has_param) header = {param, opcode, 8'h15};
      else header = {8'h00, opcode, 8'h05};
      reference_packet = {reference_ecc(header), header};
    end
  endfunction

  reg model_active = 1'b0;
  reg [31:0] model_packet = 32'h00000000;
  integer model_index = 0;
  reg expected_done = 1'b0;
  integer accepted = 0;
  integer completed = 0;
  integer aborted = 0;

  // Solo observa puertos públicos: comprueba datos incluso durante pausas.
  task check_outputs;
    begin
      if (cmd_ready !== !model_active || busy !== model_active ||
          tx_byte_valid !== model_active)
        $fatal(1, "Handshake incorrecto a t=%0t, activo=%b", $time, model_active);
      if (model_active) begin
        if (tx_byte_data !== model_packet[8*model_index +: 8])
          $fatal(1, "Byte %0d incorrecto a t=%0t: %02h != %02h", model_index,
                 $time, tx_byte_data, model_packet[8*model_index +: 8]);
        if (tx_byte_last !== (model_index == 3))
          $fatal(1, "last incorrecto en byte %0d a t=%0t", model_index, $time);
      end
    end
  endtask

  always @(posedge clk) begin
    if (rst) begin
      if (cmd_ready !== 1'b0 || tx_byte_valid !== 1'b0)
        $fatal(1, "Transferencia habilitada durante reset");
      if (model_active) aborted = aborted + 1;
      model_active = 1'b0;
      model_index = 0;
      expected_done = 1'b0;
    end else begin
      check_outputs;
      expected_done = model_active && tx_byte_ready && (model_index == 3);
      if (model_active) begin
        if (tx_byte_ready) begin
          if (model_index == 3) begin
            completed = completed + 1;
            model_active = 1'b0;
          end else model_index = model_index + 1;
        end
      end else if (cmd_valid) begin
        model_packet = reference_packet(cmd_opcode, cmd_has_param, cmd_param);
        model_index = 0;
        model_active = 1'b1;
        accepted = accepted + 1;
      end
    end

    #1;
    if (packet_done !== expected_done)
      $fatal(1, "Pulso packet_done incorrecto a t=%0t", $time);
    if (rst) begin
      if (busy !== 1'b0 || cmd_ready !== 1'b0 || tx_byte_valid !== 1'b0 ||
          tx_byte_data !== 8'h00 || tx_byte_last !== 1'b0)
        $fatal(1, "Reset no descarta completamente el paquete");
    end else check_outputs;
  end

  // El productor cambia entradas lejos del flanco de captura.
  task step;
    input reset_value;
    input valid_value;
    input [7:0] opcode_value;
    input has_param_value;
    input [7:0] param_value;
    input ready_value;
    begin
      @(negedge clk);
      rst = reset_value;
      cmd_valid = valid_value;
      cmd_opcode = opcode_value;
      cmd_has_param = has_param_value;
      cmd_param = param_value;
      tx_byte_ready = ready_value;
      @(posedge clk);
      #2;
    end
  endtask

  task send_packet;
    input [7:0] opcode;
    input has_param;
    input [7:0] param;
    input integer pauses;
    integer byte_index;
    integer pause_index;
    begin
      if (busy !== 1'b0) $fatal(1, "Productor intentó iniciar ocupado");
      step(0, 1, opcode, has_param, param, 0);
      for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
        // Cambiar el descriptor después de aceptarlo no debe alterar Q.
        for (pause_index = 0; pause_index < pauses; pause_index = pause_index + 1)
          step(0, 0, ~opcode, !has_param, ~param, 0);
        step(0, 0, ~opcode, !has_param, ~param, 1);
      end
    end
  endtask

  task check_ecc;
    input [23:0] header;
    input [7:0] expected;
    begin
      ecc_header = header;
      #1;
      if (ecc_result !== expected || reference_ecc(header) !== expected)
        $fatal(1, "ECC incorrecto para %06h: %02h != %02h", header, ecc_result, expected);
    end
  endtask

  integer i;
  integer j;
  integer position;
  initial begin
    // Matriz completa y vectores fijos, además del dominio DCS alcanzable.
    check_ecc(24'h000000, 8'h00);
    check_ecc(24'h000105, 8'h10);
    check_ecc(24'h001105, 8'h36);
    check_ecc(24'h002905, 8'h1c);
    check_ecc(24'h553a15, 8'h02);
    for (i = 0; i < 24; i = i + 1)
      check_ecc(24'h000001 << i, reference_ecc(24'h000001 << i));

    step(1, 1, 8'hff, 1, 8'hff, 1);
    step(1, 1, 8'h01, 0, 8'h00, 1);
    step(0, 0, 8'h01, 0, 8'h00, 1);
    send_packet(8'h01, 0, 8'hff, 0);
    send_packet(8'h11, 0, 8'h55, 1);
    send_packet(8'h29, 0, 8'haa, 2);
    send_packet(8'h3a, 1, 8'h55, 17);
    send_packet(8'h36, 1, 8'h00, 0);

    // Una orden siguiente se mantiene válida durante SEND; no hay cola.
    step(0, 1, 8'h3a, 1, 8'h55, 0);
    repeat (5) step(0, 1, 8'h29, 0, 8'h00, 0);
    repeat (4) step(0, 1, 8'h29, 0, 8'h00, 1);
    // IDLE + packet_done: aceptar ahora la orden pendiente y limpiar el pulso.
    step(0, 1, 8'h29, 0, 8'h00, 0);
    repeat (4) step(0, 0, 8'h00, 0, 8'h00, 1);

    // Valid y ready continuos: una aceptación cada cinco flancos.
    repeat (40) step(0, 1, 8'h3a, 1, 8'h55, 1);
    step(0, 0, 8'h00, 0, 8'h00, 1);

    // Abortar antes de cada byte, incluyendo ECC con ready=1 o ready=0.
    for (position = 0; position < 4; position = position + 1) begin
      for (j = 0; j < 2; j = j + 1) begin
        step(0, 1, 8'hff, 1, 8'hff, 0);
        for (i = 0; i < position; i = i + 1)
          step(0, 0, 8'h00, 0, 8'h00, 1);
        step(0, 0, 8'h00, 0, 8'h00, 0);
        step(1, 1, 8'h29, 0, 8'h00, (j == 1));
        step(1, 1, 8'h29, 0, 8'h00, 1);
        step(0, 0, 8'h00, 0, 8'h00, 1);
        send_packet(8'h01, 0, 8'h00, 0);
      end
    end
    // Reset durante packet_done tampoco permite aceptar un comando.
    step(1, 1, 8'h29, 0, 8'h00, 1);
    step(0, 0, 8'h00, 0, 8'h00, 1);

    // Todos los opcodes sin parámetro y los 65 536 pares opcode/parámetro.
    for (i = 0; i < 256; i = i + 1)
      send_packet(i[7:0], 0, ~i[7:0], i % 3);
    for (i = 0; i < 256; i = i + 1)
      for (j = 0; j < 256; j = j + 1)
        send_packet(i[7:0], 1, j[7:0], 0);

    repeat (3) step(0, 0, 8'h00, 0, 8'h00, 1);
    if (model_active || accepted != completed + aborted || aborted != 8)
      $fatal(1, "Contabilidad de paquetes incorrecta");
    $display("PASS dsi_lp_packet_tx: %0d completos, %0d abortados; ECC, pausas, reset y órdenes consecutivas",
             completed, aborted);
    $finish;
  end

  initial begin
    #20000000;
    $fatal(1, "Timeout del testbench");
  end

endmodule
