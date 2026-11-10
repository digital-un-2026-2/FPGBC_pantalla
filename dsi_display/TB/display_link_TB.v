`timescale 1ns/1ps
module display_link_TB #(parameter WIDTH=720, HEIGHT=2);
  localparam WC=3*WIDTH, E=HEIGHT+2;
  localparam LIMIT=HEIGHT*(4*WC+300)+1000;
  function [E*66-1:0] events;
    input bad;
    integer n;
    reg [31:0] release_tick, deadline;
    reg [1:0] kind;
    begin
      events=0;
      for(n=0;n<E;n=n+1) begin
        kind=n==0 ? 0 : n==E-1 ? 2 : 1;
        release_tick=bad ? 20 : n==E-1 ? LIMIT-100 : 20;
        deadline=bad ? 50 : n==0 ? 50 : LIMIT;
        events[n*66 +: 66]={kind,release_tick,deadline};
      end
    end
  endfunction
  reg ref_clk=0,rst=1,valid=0;
  always #12.5 ref_clk=~ref_clk;
  reg [31:0] command=0;
  wire ready,reply,clk,byte_rst,available,clock_fault;
  wire [127:0] response;
  wire [2:0] lp_p,lp_n,hs_p,hs_n;
  dsi_display_top #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.J(`GOWIN_MODEL_J),.PROFILE_OK(1),
    .N_PROFILES(2),.E_MAX(E),.N_EVENTS_TABLE({16'(E),16'(E)}),
    .T_FRAME_TABLE({32'd50,32'(LIMIT)}),.TIMING_OK_TABLE(2'b11),.TARGET_OK_TABLE(2'b11),
    .EVENT_TABLE({events(1),events(0)})) dut (
    .ref_clk(ref_clk),.rst(rst),.command(command),.command_valid(valid),.command_ready(ready),
    .response(response),.response_valid(reply),.byte_clk(clk),.rst_byte(byte_rst),
    .phy_available(available),.clock_fault(clock_fault),
    .lp_pad_p(lp_p),.lp_pad_n(lp_n),.hs_pad_p(hs_p),.hs_pad_n(hs_n));
  wire [2:0] blocked_lp_p,blocked_lp_n,blocked_hs_p,blocked_hs_n;
  wire blocked_available;
  dsi_display_top blocked (
    .ref_clk(ref_clk),.rst(rst),.command(32'd5),.command_valid(1'b1),.command_ready(),
    .response(),.response_valid(),.byte_clk(),.rst_byte(),.phy_available(blocked_available),.clock_fault(),
    .lp_pad_p(blocked_lp_p),.lp_pad_n(blocked_lp_n),.hs_pad_p(blocked_hs_p),.hs_pad_n(blocked_hs_n));
  reg [127:0] result;
  task transact(input [31:0] word,input reject);
    begin
      @(negedge ref_clk);#1;command=word;valid=1;
      @(posedge ref_clk);while(!ready) @(posedge ref_clk);
      @(negedge ref_clk);#1;valid=0;command=32'hffffffff;
      wait(reply);#1;result=response;
      if(result[9]!==reject) $fatal(1,"command %h rejection=%b expected=%b status=%h",word,result[9],reject,result[31:0]);
      @(negedge ref_clk);#1;
    end
  endtask
  task configure(input [7:0] profile);
    begin
      transact(1 | (profile<<4) | (2<<12),0);
      transact(2,0);
      if(!result[2]) $fatal(1,"profile not applied");
      transact(3,0);
      transact(5,0);
    end
  endtask
  task reset_chain;
    begin
      @(negedge ref_clk);#1;rst=1;valid=0;
      repeat(6) @(negedge ref_clk);
      #1;rst=0;
      wait(available);wait(dut.stop_ready);wait(ready);repeat(5) @(negedge ref_clk);
    end
  endtask
  function [7:0] reference_byte;
    input integer n;
    reg [23:0] color;
    begin
      case ((n / 3) * 8 / WIDTH)
        0: color = 24'hffffff; 1: color = 24'hffff00;
        2: color = 24'h00ffff; 3: color = 24'h00ff00;
        4: color = 24'hff00ff; 5: color = 24'hff0000;
        6: color = 24'h0000ff; default: color = 24'h000000;
      endcase
      reference_byte = color >> (16 - 8*(n % 3));
    end
  endfunction

  // Oraculo ECC por columnas de sindrome y CRC en direccion MSB (1021),
  // independiente de las ecuaciones XOR y del CRC reflejado del preparador.
  function [7:0] reference_ecc;
    input [23:0] header;
    integer b;
    reg [7:0] syndrome;
    begin
      reference_ecc = 0;
      for (b = 0; b < 24; b = b + 1) begin
        case (b)
          0: syndrome=8'h07; 1: syndrome=8'h0b; 2: syndrome=8'h0d; 3: syndrome=8'h0e;
          4: syndrome=8'h13; 5: syndrome=8'h15; 6: syndrome=8'h16; 7: syndrome=8'h19;
          8: syndrome=8'h1a; 9: syndrome=8'h1c; 10: syndrome=8'h23; 11: syndrome=8'h25;
          12: syndrome=8'h26; 13: syndrome=8'h29; 14: syndrome=8'h2a; 15: syndrome=8'h2c;
          16: syndrome=8'h31; 17: syndrome=8'h32; 18: syndrome=8'h34; 19: syndrome=8'h38;
          20: syndrome=8'h1f; 21: syndrome=8'h2f; 22: syndrome=8'h37; default: syndrome=8'h3b;
        endcase
        if (header[b]) reference_ecc = reference_ecc ^ syndrome;
      end
    end
  endfunction
  function [15:0] crc_msb_update;
    input [15:0] crc;
    input [7:0] data;
    reg [15:0] c;
    integer b;
    begin
      c = crc;
      for (b = 0; b < 8; b = b + 1) begin
        if (c[15] ^ data[b]) c = (c << 1) ^ 16'h1021;
        else c = c << 1;
      end
      crc_msb_update = c;
    end
  endfunction
  function [15:0] reflect16;
    input [15:0] value;
    integer b;
    begin
      for (b = 0; b < 16; b = b + 1) reflect16[b] = value[15-b];
    end
  endfunction

  // End-to-end oracle observes only serial HS pads, not packetizer data.
  reg [7:0] shift0=0,shift1=0;
  reg synced=0;
  integer bits=0,index=0,serial_packets=0,reset_packets=0;
  reg [15:0] crc=16'hffff,reflected_crc;
  reg [31:0] header;
  function [7:0] expected(input integer pos);
    begin
      header={reference_ecc({16'(WC),2'd2,6'h3e}),16'(WC),2'd2,6'h3e};
      reflected_crc=reflect16(crc);
      if(pos<4) expected=header[8*pos +: 8];
      else if(pos<WC+4) expected=reference_byte(pos-4);
      else if(pos==WC+4) expected=reflected_crc[7:0];
      else expected=reflected_crc[15:8];
    end
  endfunction
  task consume(input [7:0] value);
    begin
      if(index>=WC+6 || value!==expected(index))
        $fatal(1,"serial packet %0d byte %0d: %h != %h",serial_packets,index,value,expected(index));
      if(index>=4 && index<WC+4) crc=crc_msb_update(crc,value);
      index=index+1;
      if(index==WC+6) serial_packets=serial_packets+1;
    end
  endtask
  wire serial_clock=(hs_p[2]===1'b1);
  wire data_active=(hs_p[0]!==1'bz);
  always @(posedge serial_clock or negedge serial_clock) begin
    if(!rst && !byte_rst && data_active) begin
      shift0={hs_p[0],shift0[7:1]};shift1={hs_p[1],shift1[7:1]};
      if(!synced) begin
        if(shift0==8'hb8 && shift1==8'hb8) begin synced=1;bits=0;index=0;crc=16'hffff;end
      end else if(index<WC+6) begin
        bits=bits+1;
        if(bits==8) begin consume(shift0);consume(shift1);bits=0;end
      end
    end
  end
  always @(negedge data_active or posedge rst or posedge byte_rst) begin
    #0.0005;
    if(!rst && !byte_rst && synced && index!=WC+6) $fatal(1,"serial truncation");
    synced=0;bits=0;shift0=0;shift1=0;
  end
  // Decode LPDT Mark/Space from physical-model pads, including escape selector.
  reg [1:0] previous_lp=3;
  reg [1:0] runs[0:84];
  reg [39:0] decoded;
  wire [1:0] lp={lp_p[0],lp_n[0]};
  integer run_count=0,lp_packets=0,b;
  reg [39:0] expected_lp=40'h1000010587;
  always @(negedge clk) begin
    #1;
    if(rst || byte_rst || lp===2'bzz) begin previous_lp=3;run_count=0;end
    else if(!dut.core.lp_grant && run_count==0) previous_lp=3;
    else if(lp!==previous_lp) begin
      if(lp==3) begin
        if(run_count!=85) $fatal(1,"LP escape size %0d",run_count);
        decoded=0;
        for(b=0;b<40;b=b+1) begin
          if((runs[4+2*b]!==1 && runs[4+2*b]!==2) || runs[5+2*b]!==0)
            $fatal(1,"LP mark/space");
          decoded[b]=(runs[4+2*b]==2);
        end
        if(decoded!==expected_lp) $fatal(1,"LP packet %h",decoded);
        lp_packets=lp_packets+1;run_count=0;
      end else begin
        if(run_count>=85) $fatal(1,"LP overflow");
        runs[run_count]=lp;run_count=run_count+1;
      end
      previous_lp=lp;
    end
    if(!rst && (blocked_available || {blocked_lp_p,blocked_lp_n,blocked_hs_p,blocked_hs_n}!==12'bzzzzzzzzzzzz))
      $fatal(1,"default profile enabled pads");
    if(!rst && dut.core.lp_grant && (hs_p!==3'bzzz)) $fatal(1,"LP/HS overlap");
  end
  integer target,n;
  initial begin
    reset_chain;
    transact(5,1); // No panel authorization or applied profile.
    transact(15,1);
    transact(32'h17,0); // LP Software Reset; count only after physical release.
    transact(5,1);
    transact(0,0);
    while(result[95:64]!=1) transact(0,0);
    if(lp_packets!=1 || result[3]) $fatal(1,"LP completion/authorization");
    transact(3,0);
    expected_lp={reference_ecc(24'h773a15),24'h773a15,8'h87};
    transact(7 | (8'h3a<<4) | (1<<12) | (8'h77<<13),0);
    while(result[95:64]!=2) transact(0,0);
    if(lp_packets!=2 || result[3]) $fatal(1,"DCS parameter/authorization");
    configure(0);
    transact(7,1);transact(1,1); // No init/config writes during video.
    // Repeated frames from a single START.
    while(result[63:32]<2) transact(0,0);
    transact(6,0);
    while(!result[1]) transact(0,0);
    if(result[4] || result[63:32]<2 || serial_packets!=HEIGHT*result[63:32])
      $fatal(1,"frame/packet accounting frames=%d packets=%d flags=%h",result[63:32],serial_packets,result[31:0]);
    target=serial_packets;
    repeat(100) @(negedge ref_clk);
    if(serial_packets!=target) $fatal(1,"STOP did not stop");
    transact(5,0);transact(6,0); // Reuse applied configuration, stop first frame.
    while(!result[1]) transact(0,0);
    if(serial_packets!=target+HEIGHT) $fatal(1,"restart frame");
    // An enabled but impossible synthetic timing profile must fault, not succeed.
    configure(1);
    while(!result[4]) transact(0,0);
    if(result[13:10]!=4 || result[3] || result[2]) $fatal(1,"deadline diagnosis %h",result[31:0]);
    transact(5,1);
    reset_chain;
    configure(0);
    wait(data_active); // PLL loss while a real packet is being serialized.
    @(negedge ref_clk);#1;
    dut.hs_phy.wrapper.clocks.pll0.locked=0;dut.hs_phy.wrapper.clocks.pll0.halted=1;
    #0.01;
    if(!clock_fault || !byte_rst || {lp_p,lp_n,hs_p,hs_n}!==12'bzzzzzzzzzzzz)
      $fatal(1,"PLL loss did not block pads/reset chain");
    repeat(5) @(negedge ref_clk);
    dut.hs_phy.wrapper.clocks.pll0.locked=1;dut.hs_phy.wrapper.clocks.pll0.halted=0;
    repeat(30) @(negedge ref_clk);
    transact(0,0);
    if(!result[8] || result[3] || result[2]) $fatal(1,"lost PLL status/authorization");
    transact(5,1);
    reset_chain;
    target=serial_packets;
    configure(0);transact(6,0);
    while(!result[1]) transact(0,0);
    if(result[63:32]!=1 || serial_packets!=target+HEIGHT || result[4]) $fatal(1,"fault recovery");
    // Reset during a partially prepared line, then recover without stale data.
    transact(5,0);wait(dut.core.packet_busy);
    reset_chain;
    target=serial_packets;
    configure(0);transact(6,0);
    while(!result[1]) transact(0,0);
    if(result[63:32]!=1 || serial_packets!=target+HEIGHT) $fatal(1,"partial packet reset recovery");
    $display("PASS display: J=%0d; RGB888/ECC/CRC reconstructed from pads, LP init, repeat, STOP/restart, rejected commands, deadline, PLL loss, reset recovery, default pads blocked",`GOWIN_MODEL_J);
    $finish;
  end
  initial begin #15000000;$fatal(1,"display timeout flags=%h frames=%d",result[31:0],result[63:32]);end
endmodule
