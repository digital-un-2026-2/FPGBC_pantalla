`timescale 1ns / 1fs

module hs_phy_link_TB;
  reg clk = 0;
  always #12.5 clk = ~clk;
  reg rst = 1;
  reg cmd_valid = 0, cmd_has_param = 0;
  reg [7:0] cmd_opcode = 0, cmd_param = 0;
  wire cmd_ready, byte_valid, byte_last, byte_ready;
  wire [7:0] byte_data;
  wire lp_req, lp_done, lp_grant, bridge_busy, packet_error;
  wire [1:0] lp;
  wire hs_req;
  wire hs_done;
  wire hs_data_ready, transport_error;
  wire hs_req_ready, hs_grant, lp_complete, hs_complete;
  wire clk_start_req, data_start_req, data_stop_req, clk_stop_req;
  wire mode_busy, error, phy_abort;
  wire [1:0] error_code;

  wire clk_prepared, data_prepared, data_stopped, clk_stopped;
  wire mock_clk_active, mock_data_active, local_stop, phy_error, clk_toggle;
  wire [2:0] phy_code;
  wire [15:0] frame;
  wire [1:0] frame_kind, lp_clock, lp_data0, lp_data1;
  wire stop_ready = local_stop && !lp_grant && (lp == 2'b11);
  reg pll_locked=1;
  wire combined_error = transport_error || phy_error;


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
      .hs_error(combined_error), .hs_data_ready(hs_data_ready), .pll_locked(pll_locked),
      .hs_grant(hs_grant), .hs_complete(hs_complete),
      .clk_start_req(clk_start_req), .clk_prepared(clk_prepared),
      .data_start_req(data_start_req), .data_prepared(data_prepared),
      .data_stop_req(data_stop_req), .data_stopped(data_stopped),
      .clk_stop_req(clk_stop_req), .clk_stopped(clk_stopped), .stop_ready(stop_ready),
      .clear_error(1'b0), .busy(mode_busy), .error(error),
      .error_code(error_code), .phy_abort(phy_abort)
  );


  reg select_long=0, source_cmd=0, source_payload_valid=0;
  reg [15:0] wc=0;
  reg [7:0] payload=0;
  wire sr,lr,sv,lv,sl,ll,sbr,lbr,pr;
  wire [7:0] sb,lb;
  wire wv,wl,wr,transport_busy,transport_done;
  wire [15:0] wd,od;
  wire [1:0] wk,ok,transport_code;
  wire ov,ol;
  dsi_lp_packet_tx hs_short(.clk(clk),.rst(rst),.cmd_valid(source_cmd&&!select_long),
    .cmd_ready(sr),.cmd_opcode(8'h29),.cmd_has_param(1'b0),.cmd_param(8'd0),
    .tx_byte_data(sb),.tx_byte_valid(sv),.tx_byte_last(sl),.tx_byte_ready(sbr),.busy(),.packet_done());
  dsi_long_packet_tx hs_long(.clk(clk),.rst(rst),.cmd_valid(source_cmd&&select_long),
    .cmd_ready(lr),.cmd_vc(2'd0),.cmd_dt(6'h3e),.cmd_wc(wc),
    .payload_data(payload),.payload_valid(source_payload_valid),.payload_ready(pr),
    .tx_byte_data(lb),.tx_byte_valid(lv),.tx_byte_last(ll),.tx_byte_ready(lbr),.busy(),.packet_done());
  wire bv=select_long?lv:sv;
  wire bl=select_long?ll:sl;
  wire [7:0] bd=select_long?lb:sb;
  wire br;
  assign sbr=br&&!select_long;
  assign lbr=br&&select_long;
  dsi_lane_packer packer(.clk(clk),.rst(rst),.tx_byte_data(bd),.tx_byte_valid(bv),
    .tx_byte_last(bl),.tx_byte_ready(br),.tx_word_data(wd),.tx_word_keep(wk),
    .tx_word_valid(wv),.tx_word_last(wl),.tx_word_ready(wr));
  dsi_hs_transport transport(.clk(clk),.rst(rst),.tx_word_data(wd),.tx_word_keep(wk),
    .tx_word_valid(wv),.tx_word_last(wl),.tx_word_ready(wr),
    .hs_req(hs_req),.hs_req_ready(hs_req_ready),.hs_data_ready(hs_data_ready),
    .hs_grant(hs_grant),.hs_done(hs_done),.hs_error(transport_error),
    .hs_complete(hs_complete),.phy_abort(phy_abort),.hs_word_data(od),
    .hs_word_keep(ok),.hs_word_valid(ov),.hs_word_last(ol),
    .busy(transport_busy),.error(),.error_code(transport_code));
  dphy_hs_tx phy(.clk(clk),.rst(rst),.phy_abort(phy_abort),
    .clk_start_req(clk_start_req),.data_start_req(data_start_req),
    .data_stop_req(data_stop_req),.clk_stop_req(clk_stop_req),
    .hs_grant(hs_grant),.hs_word_data(od),.hs_word_keep(ok),
    .hs_word_valid(ov),.hs_word_last(ol),
    .clk_prepared(clk_prepared),.data_prepared(data_prepared),
    .data_stopped(data_stopped),.clk_stopped(clk_stopped),
    .hs_local_stop(local_stop),.phy_error(phy_error),.error_code(phy_code),
    .hs_frame_data(frame),.hs_frame_kind(frame_kind),
    .hs_clk_on(mock_clk_active),.hs_data_on(mock_data_active),.clk_toggle(clk_toggle),
    .lp_clk(lp_clock),.lp_d0(lp_data0),.lp_d1(lp_data1));
  reg [7:0] expected_bytes[0:4095];
  integer input_bytes=0, output_bytes=0, hs_packets=0;
  reg streaming=0;
  always @(posedge clk) if(!rst) begin
    if(transport_error) $fatal(1,"transport fault %d",transport_code);
    if(bv&&br) begin expected_bytes[input_bytes]=bd; input_bytes=input_bytes+1; end
    if(streaming&&!ov) $fatal(1,"HS bubble");
    if(ov) begin
      if(!hs_grant || lp_grant || !data_prepared) $fatal(1,"HS ownership");
      if(output_bytes>=input_bytes || od[7:0]!==expected_bytes[output_bytes]) $fatal(1,"D0 mismatch");
      output_bytes=output_bytes+1;
      if(ok==3) begin
        if(output_bytes>=input_bytes || od[15:8]!==expected_bytes[output_bytes]) $fatal(1,"D1 mismatch");
        output_bytes=output_bytes+1;
      end else if(ok!=1 || !ol) $fatal(1,"invalid mask");
      streaming=!ol;
      if(ol) begin
        if(output_bytes!=input_bytes) $fatal(1,"length mismatch");
        hs_packets=hs_packets+1;
      end
    end
  end
  task send_hs(input integer length);
    integer p;
    begin
      drive; select_long=(length>=0); wc=length; source_cmd=1;
      @(posedge clk); while(!(select_long?lr:sr)) @(posedge clk);
      drive; source_cmd=0;
      for(p=0;p<length;p=p+1) begin
        repeat(p%3) tick;
        drive; payload=(p*37)^8'ha5; source_payload_valid=1;
        @(posedge clk); while(!pr) @(posedge clk);
        drive; source_payload_valid=0;
      end
    end
  endtask
  integer lp_finished = 0, hs_finished = 0, hs_accepted = 0;
  integer decoded_frames = 0, pending_during_hs = 0, pending_during_lp = 0;
  reg [31:0] expected_packet = 0;
  reg [1:0] previous_lp = 2'b11;
  reg [1:0] runs [0:84];
  integer run_count = 0, run_cycles = 0, bit_index;
  reg [39:0] decoded;

  always @(posedge clk) begin
    if (!rst && hs_req && hs_req_ready) hs_accepted = hs_accepted+1;
    @(negedge clk); #1;
    if (!rst) begin
      if (error || packet_error || error_code || phy_error) $fatal(1, "Error en prueba integrada");
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

  localparam real UI=3.125;
  reg serial_clock=0, serial_d0=0, serial_d1=0;
  reg [15:0] serial_frame;
  integer ui_index;
  // Conductual 8:1. No delays or generated clocks occur in src/ RTL.
  always @(posedge clk) begin
    #0.001;
    serial_frame=frame;
    for(ui_index=0;ui_index<8;ui_index=ui_index+1) begin
      serial_d0=serial_frame[ui_index]; serial_d1=serial_frame[8+ui_index];
      #(UI/2);
      if(mock_clk_active && clk_toggle) serial_clock=~serial_clock;
      if(ui_index<7) #(UI/2);
    end
  end
  reg [7:0] shift0=0, shift1=0;
  integer serial_bits=0, serial_bytes=0, serial_packets=0;
  reg synced=0;
  realtime last_edge=0;
  always @(posedge serial_clock or negedge serial_clock) begin
    if(!rst && mock_data_active) begin
      if(last_edge!=0 && ($realtime-last_edge<3.124 || $realtime-last_edge>3.126))
        $fatal(1,"serial clock cadence");
      last_edge=$realtime;
      shift0={serial_d0,shift0[7:1]}; shift1={serial_d1,shift1[7:1]};
      if(!synced) begin
        if(shift0==8'hb8 && shift1==8'hb8) begin synced=1; serial_bits=0; end
      end else if(serial_bytes<input_bytes) begin
        serial_bits=serial_bits+1;
        if(serial_bits==8) begin
          if(shift0!==expected_bytes[serial_bytes] || shift1!==expected_bytes[serial_bytes+1])
            $fatal(1,"serial bytes %0d: %h %h",serial_bytes,shift0,shift1);
          serial_bytes=serial_bytes+2; serial_bits=0;
          if(serial_bytes==input_bytes) serial_packets=serial_packets+1;
        end
      end
    end
  end
  always @(negedge mock_data_active) begin
    #0.0005;
    if(!mock_data_active) begin
    if(!rst && synced && serial_bytes!=input_bytes) $fatal(1,"serial truncation %0d / %0d",serial_bytes,input_bytes);
    synced=0; serial_bytes=0; serial_bits=0; shift0=0;shift1=0;last_edge=0;
    end
  end
  // Check physical-model interval boundaries independently of UC state.
  realtime clk_rise, data_rise, data_fall, clock_stop;
  reg last_data_hs=0, last_clock_hs=0, last_toggle=0;
  integer trail_words=0;
  always @(posedge clk) begin
    #0.002;
    if(!rst) begin
      if(mock_data_active && !last_data_hs) data_rise=$realtime;
      if(!mock_data_active && last_data_hs) begin
        data_fall=$realtime;
        if(trail_words!=3) $fatal(1,"Trail length %0d",trail_words);
        trail_words=0;
      end
      if(mock_data_active && frame_kind==3) trail_words=trail_words+1;
      if(clk_toggle && !last_toggle) clk_rise=$realtime;
      if(!clk_toggle && last_toggle) begin
        clock_stop=$realtime;
        if(clock_stop-data_fall<224.999) $fatal(1,"CLK-POST too short");
      end
      if(data_prepared && !mock_clk_active) $fatal(1,"data prepared without clock");
      if(lp_grant && (mock_clk_active || mock_data_active)) $fatal(1,"LP/HS conflict");
    end
    last_data_hs=mock_data_active; last_clock_hs=mock_clk_active; last_toggle=clk_toggle;
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
      while ((lp_finished < lp_target || hs_finished < hs_target) && timeout < 5000) begin
        tick; timeout = timeout+1;
      end
      if (lp_finished != lp_target || hs_finished != hs_target)
        $fatal(1, "Timeout o fin duplicado en integracion");
      repeat (3) tick;
      if (mode_busy || bridge_busy || !stop_ready)
        $fatal(1, "No libera enlace despues de ambas operaciones");
    end
  endtask


  string vcd_path;
  initial begin
    if ($value$plusargs("vcd=%s", vcd_path)) begin
      $dumpfile(vcd_path);
      $dumpvars(0, hs_phy_link_TB);
    end
  end
  integer round_index;
  initial begin
    repeat(3) tick; drive; rst=0; wait(local_stop); repeat(3) tick;
    for(round_index=0;round_index<6;round_index=round_index+1) begin
      expected_packet=32'h10000105;
      // LP starts first; HS reserves only after the real LPDT has returned.
      command(8'h01,0,0);
      case(round_index)
        0: send_hs(-1);
        1: send_hs(0);
        2: send_hs(2);
        3: send_hs(18);
        4: send_hs(2160);
        5: send_hs(4090);
      endcase
      wait_finished(round_index+1,round_index+1);
      repeat(4) tick;
      if(transport_busy || hs_packets!=round_index+1) $fatal(1,"transport release");
      input_bytes=0; output_bytes=0;
    end
    // HS starts first; a real LP packet must wait for its release.
    send_hs(-1);
    wait(hs_grant); command(8'h01,0,0);
    wait_finished(7,7);
    if(hs_packets!=7 || hs_accepted!=7 || pending_during_lp==0 || pending_during_hs==0)
      $fatal(1,"coverage / duplicate request");
    if(serial_packets!=7) $fatal(1,"serial packet count");
    $display("PASS PHY link: 7 serialized HS packets, 7 decoded LPDT; WC=0/2/18/2160/4090");
    $finish;
  end
  initial begin #5000000; $fatal(1,"link watchdog"); end
endmodule
