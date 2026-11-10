`timescale 1ns/1ps

// Autonomous fixed-image source. One ROM contains a complete RGB888 line.
// There is no packet preparation or buffer refill on the video critical path.
module display_image_control #(
    parameter integer ACTIVE_LINES=720,
    parameter integer LINE_HZ=45000,
    parameter integer INIT_CYCLES_PER_MS=60000,
    parameter integer BACKLIGHT_DCS=0
) (
    input clk, rst, phy_ready, stop_ready, external_error,
    input start, stop,
    output lp_req, input lp_grant, input lp_complete,
    output lp_done, output [1:0] estado_D0,
    output hs_req, input hs_req_ready, hs_grant, hs_complete,
    output hs_data_ready, output reg hs_done,
    output [15:0] hs_word, output hs_valid, hs_last,
    output reg initialized, running, output stopped,
    output reg error, output reg [3:0] error_cause,
    output reg [31:0] frames, lp_count,
    output [3:0] init_step, output [9:0] raster_line,
    output [3:0] state_debug
);
  localparam integer V_SYNC=5, V_BACK=3, V_FRONT=22;
  localparam integer V_TOTAL=ACTIVE_LINES+V_SYNC+V_BACK+V_FRONT;
  localparam [3:0] WAIT_PHY=0, LP_REQUEST=1, LP_TRANSMIT=2, INIT_DELAY=3,
      WAIT_LINE=4, PRIME=5, REQUEST=6, WAIT_GRANT=7, SEND=8, WAIT_COMPLETE=9, HALTED=10;
  reg [3:0] state, init_index;
  reg [31:0] delay_ticks, line_phase;
  reg [9:0] line_index;
  reg stop_pending;
  reg active_line;
  reg [1:0] sync_kind;
  reg [10:0] word_index;
  wire [10:0] final_index=11'd1162;
  wire [10:0] read_address=(hs_valid && !hs_last) ? word_index+11'd1 : word_index;
  wire [7:0] init_byte, init_delay_ms;
  wire [3:0] init_length, init_position;
  wire motor_accepted;
  // The ratio is exact over a frame: periods 1334,1333,1333 at 60MHz/45kHz.
  wire line_tick=running && line_phase >= 60000000-LINE_HZ;
  wire stop_next=stop_pending || stop;
  assign lp_req=!rst && state==LP_REQUEST;
  assign hs_req=!rst && !error && state==REQUEST;
  assign hs_data_ready=!rst && !error && state>=REQUEST && state<=SEND;
  assign hs_valid=!rst && !error && state==SEND && hs_grant;
  assign hs_last=word_index==final_index;
  assign stopped=initialized && !running && !error && state==WAIT_LINE;
  assign init_step=init_index;
  assign raster_line=line_index;
  assign state_debug=state;
  display_image_rom rom (
    .clk(clk),.address(read_address),.active(active_line),.sync_kind(sync_kind),.word(hs_word),
    .init_index(init_index),.init_position(init_position),.init_byte(init_byte),
    .init_length(init_length),.init_delay_ms(init_delay_ms));
  dphy_lpdt_tx #(.ANCHO_LONGITUD(4)) motor (
    .clk(clk),.rst(rst),.permiso_arranque(lp_grant),.solicitud(lp_req),
    .cantidad_bytes(init_length),.byte_almacen(init_byte),.pos(init_position),
    .aceptado(motor_accepted),.ocupado(),.terminado(lp_done),.estado_D0(estado_D0));

  generate if(ACTIVE_LINES<1 || V_TOTAL>1024 || LINE_HZ<1 || LINE_HZ>60000000 || INIT_CYCLES_PER_MS<1) begin: invalid
    DISPLAY_IMAGE_INVALID_PARAMETERS invalid_config ();
  end endgenerate
  always @(posedge clk) begin
    if(rst) begin
      state<=WAIT_PHY;init_index<=0;delay_ticks<=0;line_phase<=0;
      line_index<=0;word_index<=0;active_line<=0;sync_kind<=0;
      initialized<=0;running<=0;stop_pending<=0;
      hs_done<=0;error<=0;error_cause<=0;frames<=0;lp_count<=0;
    end else begin
      hs_done<=0;
      if(running) begin
        if(line_tick) line_phase<=line_phase+LINE_HZ-60000000;
        else line_phase<=line_phase+LINE_HZ;
        if(stop) stop_pending<=1;
      end
      if(error) state<=HALTED;
      else if(external_error) begin
        state<=HALTED;error<=1;error_cause<=1;running<=0;initialized<=0;
      end else if(line_tick && state!=WAIT_LINE) begin
        // An overrun is a fault, never an invented frame or skipped line.
        state<=HALTED;error<=1;error_cause<=4;running<=0;initialized<=0;
      end else begin
        case(state)
          WAIT_PHY: if(phy_ready && stop_ready) state<=LP_REQUEST;
          LP_REQUEST: if(motor_accepted) state<=LP_TRANSMIT;
          LP_TRANSMIT: if(lp_complete) begin
            lp_count<=lp_count+1;
            delay_ticks<=init_delay_ms*INIT_CYCLES_PER_MS;
            state<=INIT_DELAY;
          end
          INIT_DELAY: begin
            if(delay_ticks!=0) delay_ticks<=delay_ticks-1;
            else if(init_index==(BACKLIGHT_DCS ? 12 : 10)) begin
              initialized<=1;running<=1;state<=WAIT_LINE;line_phase<=0;
              line_index<=0;stop_pending<=0;
            end else begin init_index<=init_index+1;state<=LP_REQUEST;end
          end
          WAIT_LINE: begin
            if(start && stopped && phy_ready && stop_ready) begin
              running<=1;line_phase<=0;line_index<=0;stop_pending<=0;
            end
            if(line_tick) begin
              active_line<=line_index>=V_SYNC+V_BACK && line_index<V_SYNC+V_BACK+ACTIVE_LINES;
              sync_kind<=line_index==0 ? 2'd1 : line_index==V_SYNC ? 2'd2 : 2'd0;
              word_index<=0;state<=PRIME;
            end
          end
          PRIME: state<=REQUEST;
          REQUEST: if(hs_req_ready) state<=WAIT_GRANT;
          WAIT_GRANT: if(hs_grant) state<=SEND;
          SEND: begin
            if(!hs_grant) begin
              state<=HALTED;error<=1;error_cause<=2;running<=0;initialized<=0;
            end else if(hs_last) begin state<=WAIT_COMPLETE;hs_done<=1;end
            else word_index<=word_index+1;
          end
          WAIT_COMPLETE: if(hs_complete) begin
            state<=WAIT_LINE;
            if(line_index==V_TOTAL-1) begin
              line_index<=0;frames<=frames+1;
              if(stop_next) begin running<=0;stop_pending<=0;end
            end else line_index<=line_index+1;
          end
          HALTED: begin end
          default: begin state<=HALTED;error<=1;error_cause<=5;running<=0;initialized<=0;end
        endcase
      end
    end
  end
endmodule
