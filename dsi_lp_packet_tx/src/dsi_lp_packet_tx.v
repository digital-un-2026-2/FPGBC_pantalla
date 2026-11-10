`timescale 1ns / 1ps

// Preparador de escrituras DCS cortas, VC=0. Todos los registros: posedge clk.
module dsi_lp_packet_tx (
    input clk,
    input rst,

    input cmd_valid,
    input [7:0] cmd_opcode,
    input cmd_has_param,
    input [7:0] cmd_param,
    output cmd_ready,

    output [7:0] tx_byte_data,
    output tx_byte_valid,
    output tx_byte_last,
    input tx_byte_ready,

    output busy,
    output packet_done
);

  wire [7:0] w_data_id;
  wire [7:0] w_data_1;
  wire [23:0] w_header;
  wire [7:0] w_ecc;
  wire [31:0] w_packet;
  wire [1:0] w_indice_byte;
  wire w_ld_packet;
  wire w_rst_byte;
  wire w_inc_byte;
  wire w_z_last;

  packet_mux #(
      .INPUTS(2),
      .BITS  (8)
  ) mux_data_id (
      .data_in({8'h15, 8'h05}),
      .sel(cmd_has_param),
      .data_out(w_data_id)
  );

  packet_mux #(
      .INPUTS(2),
      .BITS  (8)
  ) mux_data_1 (
      .data_in({cmd_param, 8'h00}),
      .sel(cmd_has_param),
      .data_out(w_data_1)
  );

  assign w_header = {w_data_1, cmd_opcode, w_data_id};

  packet_ecc ecc_header (
      .header(w_header),
      .ecc(w_ecc)
  );

  packet_register #(
      .BITS(32)
  ) reg_packet (
      .clk(clk),
      .rst(rst),
      .reg_in({w_ecc, w_header}),
      .ld(w_ld_packet),
      .reg_out(w_packet)
  );

  packet_mux #(
      .INPUTS(4),
      .BITS  (8)
  ) mux_byte (
      .data_in(w_packet),
      .sel(w_indice_byte),
      .data_out(tx_byte_data)
  );

  packet_counter #(
      .BITS(2)
  ) count_indice_byte (
      .clk(clk),
      .rst(w_rst_byte),
      .inc(w_inc_byte),
      .count_out(w_indice_byte)
  );

  packet_compare #(
      .BITS(2)
  ) comp_ultimo_byte (
      .A(w_indice_byte),
      .B(2'd3),
      .z(w_z_last)
  );

  assign tx_byte_last = w_z_last;

  packet_control ctrl (
      .clk(clk),
      .rst(rst),
      .cmd_valid(cmd_valid),
      .tx_byte_ready(tx_byte_ready),
      .z_last(w_z_last),
      .ld_packet(w_ld_packet),
      .rst_byte(w_rst_byte),
      .inc_byte(w_inc_byte),
      .cmd_ready(cmd_ready),
      .tx_byte_valid(tx_byte_valid),
      .busy(busy),
      .packet_done(packet_done)
  );

endmodule
