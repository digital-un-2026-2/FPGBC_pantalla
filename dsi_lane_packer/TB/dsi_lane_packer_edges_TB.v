`timescale 1ns / 1ps

// Matriz de controles y contrato temporal; la prueba de paquetes usa solo puertos.
module dsi_lane_packer_edges_TB;
  reg clk = 0;
  always #12.5 clk = !clk;
  reg rst = 0;
  reg [7:0] data = 0;
  reg valid = 0, last = 0, ready = 0;
  wire byte_ready, word_valid, word_last;
  wire [15:0] word_data;
  wire [1:0] keep;
  dsi_lane_packer dut (
      .clk(clk), .rst(rst), .tx_byte_data(data), .tx_byte_valid(valid),
      .tx_byte_last(last), .tx_byte_ready(byte_ready), .tx_word_data(word_data),
      .tx_word_keep(keep), .tx_word_valid(word_valid), .tx_word_last(word_last),
      .tx_word_ready(ready)
  );

  task tick;
    begin @(posedge clk); #1; end
  endtask

  // Dejar una palabra completa pendiente para detectar cualquier cambio indebido.
  task seed_word;
    begin
      @(negedge clk); rst = 1; valid = 1; ready = 1;
      tick();
      if (word_data !== 0 || keep !== 1 || word_last !== 0)
        $fatal(1, "Reset no limpia datapath");
      @(negedge clk); rst = 0; data = 8'h35; last = 0; ready = 0;
      tick();
      if (word_data !== 16'h0035 || keep !== 1 || word_last !== 0)
        $fatal(1, "Primera captura retrasada o incorrecta");
      @(negedge clk); data = 8'hac; last = 1;
      tick();
      if (word_data !== 16'hac35 || keep !== 3 || word_last !== 1)
        $fatal(1, "Segunda captura retrasada o incorrecta");
    end
  endtask

  integer code, combo, cases = 0;
  reg [1:0] forced_state, next_expected;
  reg want_ready, want_valid, want_first, want_second, want_reset;
  reg [15:0] want_data;
  reg [1:0] want_keep;
  reg want_last;
  initial begin
    #1; rst = 1;
    for (code = 0; code < 4; code = code + 1) begin
      for (combo = 0; combo < 16; combo = combo + 1) begin
        seed_word();
        @(negedge clk);
        forced_state = code;
        force dut.control.state = forced_state;
        {rst, valid, last, ready} = combo[3:0];
        data = 8'h6e;
        want_ready = !rst && code < 2;
        want_valid = !rst && code == 2;
        want_first = want_ready && valid && code == 0;
        want_second = want_ready && valid && code == 1;
        want_reset = rst || code == 3;
        #1;
        if ({byte_ready, word_valid, dut.ld_first, dut.ld_second, dut.rst_dp} !==
            {want_ready, want_valid, want_first, want_second, want_reset})
          $fatal(1, "Controles incorrectos: codigo=%0d entradas=%b", code, combo[3:0]);
        if (word_data !== 16'hac35 || keep !== 3 || word_last !== 1)
          $fatal(1, "Datapath cambia antes de posedge");
        // Recuperación: retirar force antes del posedge; no escribir el estado de destino.
        release dut.control.state;
        want_data = 16'hac35; want_keep = 3; want_last = 1;
        next_expected = code;
        if (want_reset) begin
          next_expected = 0; want_data = 0; want_keep = 1; want_last = 0;
        end else if (want_first) begin
          next_expected = last ? 2 : 1;
          want_data = 16'h006e; want_keep = 1; want_last = last;
        end else if (want_second) begin
          next_expected = 2;
          want_data = 16'h6e35; want_keep = 3; want_last = last;
        end else if (want_valid && ready) next_expected = 0;
        tick();
        if (dut.control.state !== next_expected || word_data !== want_data ||
            keep !== want_keep || word_last !== want_last)
          $fatal(1, "Transicion/captura incorrecta: codigo=%0d entradas=%b", code, combo[3:0]);
        // Cambiar entradas después de aceptar: no debe haber actualización en negedge.
        #1; data = ~data; valid = 0; last = ~last;
        @(negedge clk); #1;
        if (word_data !== want_data || keep !== want_keep || word_last !== want_last ||
            dut.control.state !== next_expected)
          $fatal(1, "Memoria cambia fuera de posedge");
        cases = cases + 1;
      end
    end
    $display("PASS: %0d combinaciones de estado/reset/valid/last/ready; captura en posedge y recuperacion de 11", cases);
    $finish;
  end
  initial begin #100000; $fatal(1, "Timeout de controles"); end
endmodule
