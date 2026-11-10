`timescale 1ns / 1ps

// Puente de prueba para paquetes DSI de cuatro bytes; D0 permanece lógico.
module dsi_lpdt_bridge (
    input clk,
    input rst,

    input [7:0] tx_byte_data,
    input tx_byte_valid,
    input tx_byte_last,
    output tx_byte_ready,
    input permiso_arranque,

    output lp_req,
    output busy,
    output reg tx_done,
    output reg packet_error,
    output [1:0] estado_D0
);
  localparam [1:0] COLLECT = 2'd0;
  localparam [1:0] REQUEST = 2'd1;
  localparam [1:0] TRANSMIT = 2'd2;
  localparam [1:0] DRAIN = 2'd3;

  reg [1:0] state;
  reg [1:0] write_index;
  reg [31:0] packet;
  reg [7:0] byte_almacen;
  wire [2:0] pos;
  wire aceptado;
  wire terminado;
  wire byte_fire = tx_byte_valid && tx_byte_ready;

  assign tx_byte_ready = !rst && ((state == COLLECT) || (state == DRAIN));
  assign busy = (state != COLLECT) || (write_index != 0);
  assign lp_req = (state == REQUEST) && !rst;

  // El motor anticipa pos y captura el byte en negedge. Lectura asíncrona.
  always @(*) begin
    case (pos)
      3'd0: byte_almacen = packet[7:0];
      3'd1: byte_almacen = packet[15:8];
      3'd2: byte_almacen = packet[23:16];
      3'd3: byte_almacen = packet[31:24];
      default: byte_almacen = 8'h00;
    endcase
  end

  dphy_lpdt_tx motor (
      .clk(clk), .rst(rst),
      .permiso_arranque(permiso_arranque),
      .solicitud(lp_req),
      .cantidad_bytes(3'd4), .byte_almacen(byte_almacen),
      .aceptado(aceptado), .ocupado(), .terminado(terminado),
      .pos(pos), .estado_D0(estado_D0)
  );

  always @(posedge clk) begin
    if (rst) begin
      state <= COLLECT;
      write_index <= 0;
      packet <= 0;
      tx_done <= 0;
      packet_error <= 0;
    end else begin
      tx_done <= 0;
      packet_error <= 0;
      case (state)
        COLLECT: begin
          if (byte_fire) begin
            packet[8*write_index +: 8] <= tx_byte_data;
            if (tx_byte_last) begin
              write_index <= 0;
              if (write_index == 3) begin
                state <= REQUEST;
              end else begin
                packet <= 0;
                packet_error <= 1;
              end
            end else if (write_index == 3) begin
              // Paquete demasiado largo: consumir hasta su frontera real.
              packet <= 0;
              write_index <= 0;
              state <= DRAIN;
              packet_error <= 1;
            end else begin
              write_index <= write_index + 1'b1;
            end
          end
        end
        REQUEST: if (aceptado) state <= TRANSMIT;
        TRANSMIT: begin
          if (terminado) begin
            state <= COLLECT;
            packet <= 0;
            tx_done <= 1;
          end
        end
        DRAIN: if (byte_fire && tx_byte_last) state <= COLLECT;
        default: begin
          state <= COLLECT;
          write_index <= 0;
          packet <= 0;
        end
      endcase
    end
  end
endmodule
