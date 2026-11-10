`timescale 1ns/1ps

// Image bring-up: sourced JDI initialization + repeating 720x720 RGB888 bars.
// Active HS, 480 Mbit/s/lane, CLKOUTP nominally 90 degrees from CLKOUT.
module dsi_image_top #(
    parameter integer ACTIVE_LINES=720, LINE_HZ=45000, INIT_CYCLES_PER_MS=60000,
    parameter integer BACKLIGHT_DCS=0,
    parameter J=0, parameter PLL_PHASE="0100", SER_HWL="false",
    parameter [23:0] MAP_BITS=24'hfac688
) (
    input ref_clk, rst,
    input [31:0] command, input command_valid, output command_ready,
    output [127:0] response, output response_valid,
    output byte_clk, rst_byte, phy_available, clock_fault,
    output [2:0] lp_pad_p, lp_pad_n, hs_pad_p, hs_pad_n
);
  wire ref_rst, byte_valid, byte_ready;
  wire core_rst=rst | rst_byte;
  wire [31:0] byte_command;
  wire [127:0] byte_response;
  reg reply_pending, rejected;
  wire [3:0] op=byte_command[3:0];
  wire stopped, running, initialized, controller_error;
  wire [3:0] controller_cause, init_step;
  wire [3:0] source_state;
  wire [9:0] raster_line;
  wire [31:0] frames, lp_count;
  wire lp_req, lp_done, lp_grant, lp_complete;
  wire hs_req, hs_req_ready, hs_grant, hs_complete, hs_data_ready, hs_done;
  wire cs, ds, dt, ct, cp, dp, dst, cst, stop_ready;
  wire rcp, rdp, rds, rcs, local_stop, phy_error, mode_error, mode_busy, phy_abort;
  wire [1:0] mode_code, estado_D0;
  wire [2:0] phy_code;
  wire [15:0] word, frame;
  wire valid, last;
  wire [1:0] kind, lp_clk, lp_d0, lp_d1;
  wire hs_on, clock_on, toggle;
  reg link_ready;
  wire start=byte_valid && byte_ready && op==5 && stopped && phy_available;
  wire stop=byte_valid && byte_ready && op==6;
  wire combined_error=controller_error || phy_error || mode_error || clock_fault;
  // Image diagnostic format: bit30=1; state[29:26], BL mode[25], init step[24:21].
  wire [31:0] flags={1'b0,1'b1,source_state,(BACKLIGHT_DCS!=0),init_step,2'd0,mode_code,phy_code,controller_cause,
      rejected,clock_fault,mode_busy,!initialized,phy_available,combined_error,
      initialized,1'b1,stopped,running};
  localparam [15:0] HEIGHT=ACTIVE_LINES;
  assign byte_response={{HEIGHT,16'd720},lp_count,frames,flags};
  assign byte_ready=!core_rst && !reply_pending;
  always @(posedge byte_clk) begin
    if(core_rst) begin reply_pending<=0;rejected<=0;link_ready<=0;end
    else begin
      link_ready<=phy_available;
      reply_pending<=byte_valid && byte_ready;
      if(byte_valid && byte_ready) rejected<=!(op==0 || start || op==6);
    end
  end
  gowin_tx_reset_sync ref_reset (.clk(ref_clk),.request(core_rst),.rst(ref_rst));
  display_mailbox mailbox (
    .ref_clk(ref_clk),.ref_rst(ref_rst),.byte_clk(byte_clk),.byte_rst(core_rst),
    .command(command),.command_valid(command_valid),.command_ready(command_ready),
    .response(response),.response_valid(response_valid),.byte_command(byte_command),
    .byte_valid(byte_valid),.byte_ready(byte_ready),.byte_response(byte_response),
    .byte_response_valid(reply_pending));
  display_image_control #(.ACTIVE_LINES(ACTIVE_LINES),.LINE_HZ(LINE_HZ),
      .INIT_CYCLES_PER_MS(INIT_CYCLES_PER_MS),.BACKLIGHT_DCS(BACKLIGHT_DCS)) source (
    .clk(byte_clk),.rst(core_rst),.phy_ready(phy_available),.stop_ready(stop_ready),
    .external_error(phy_error || mode_error || clock_fault),.start(start),.stop(stop),
    .lp_req(lp_req),.lp_grant(lp_grant),.lp_complete(lp_complete),.lp_done(lp_done),.estado_D0(estado_D0),
    .hs_req(hs_req),.hs_req_ready(hs_req_ready),.hs_grant(hs_grant),.hs_complete(hs_complete),
    .hs_data_ready(hs_data_ready),.hs_done(hs_done),.hs_word(word),.hs_valid(valid),.hs_last(last),
    .initialized(initialized),.running(running),.stopped(stopped),.error(controller_error),
    .error_cause(controller_cause),.frames(frames),.lp_count(lp_count),.init_step(init_step),.raster_line(raster_line),.state_debug(source_state));
  dphy_mode_ctrl arbiter (
    .clk(byte_clk),.rst(core_rst),.lp_req(lp_req),.lp_req_ready(),.lp_done(lp_done),
    .lp_grant(lp_grant),.lp_complete(lp_complete),.hs_req(hs_req),.hs_req_ready(hs_req_ready),
    .hs_done(hs_done),.hs_error(controller_error || phy_error || clock_fault),
    .hs_data_ready(hs_data_ready),.pll_locked(link_ready),.hs_grant(hs_grant),.hs_complete(hs_complete),
    .clk_start_req(cs),.data_start_req(ds),.data_stop_req(dt),.clk_stop_req(ct),
    .clk_prepared(cp),.data_prepared(dp),.data_stopped(dst),.clk_stopped(cst),.stop_ready(stop_ready),
    .clear_error(1'b0),.busy(mode_busy),.error(mode_error),.error_code(mode_code),.phy_abort(phy_abort));
  dphy_hs_tx #(.BYTE_HZ(60000000)) phy (
    .clk(byte_clk),.rst(core_rst),.phy_abort(phy_abort),.clk_start_req(cs),.data_start_req(ds),
    .data_stop_req(dt),.clk_stop_req(ct),.hs_grant(hs_grant),.hs_word_data(word),
    .hs_word_keep(2'b11),.hs_word_valid(valid),.hs_word_last(last),
    .clk_prepared(rcp),.data_prepared(rdp),.data_stopped(rds),.clk_stopped(rcs),
    .hs_local_stop(local_stop),.phy_error(phy_error),.error_code(phy_code),
    .hs_frame_data(frame),.hs_frame_kind(kind),.hs_data_on(hs_on),.hs_clk_on(clock_on),
    .clk_toggle(toggle),.lp_clk(lp_clk),.lp_d0(lp_d0),.lp_d1(lp_d1));
  dphy_gowin_tx #(.J(J),.PROFILE_OK(1),.PLL_FBDIV(5),.PLL_PHASE(PLL_PHASE),
      .SER_HWL(SER_HWL),.MAP_BITS(MAP_BITS)) wrapper (
    .ref_clk(ref_clk),.rst(rst),.phy_abort(phy_abort),.lp_grant(lp_grant),.estado_D0(estado_D0),
    .hs_frame_data(frame),.hs_frame_kind(kind),.hs_data_on(hs_on),.hs_clk_on(clock_on),.clk_toggle(toggle),
    .lp_clk(lp_clk),.lp_d0(lp_d0),.lp_d1(lp_d1),.clk_prepared_s(rcp),.data_prepared_s(rdp),
    .data_stopped_s(rds),.clk_stopped_s(rcs),.local_stop_s(local_stop),
    .byte_clk(byte_clk),.rst_byte(rst_byte),.clk_prepared_p(cp),.data_prepared_p(dp),
    .data_stopped_p(dst),.clk_stopped_p(cst),.stop_ready(stop_ready),.pll_ready(phy_available),
    .clock_fault(clock_fault),.lp_pad_p(lp_pad_p),.lp_pad_n(lp_pad_n),.hs_pad_p(hs_pad_p),.hs_pad_n(hs_pad_n));
endmodule
