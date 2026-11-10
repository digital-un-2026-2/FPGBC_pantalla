`timescale 1ns/1ps
module display_image_TB;
`ifdef IMAGE_BACKLIGHT_TEST
  localparam BACKLIGHT=1, INIT_COUNT=13;
`else
  localparam BACKLIGHT=0, INIT_COUNT=11;
`endif
  localparam HEIGHT=2, TOTAL=HEIGHT+30;
  reg ref_clk=0,rst=1,valid=0;
  always #12.5 ref_clk=~ref_clk;
  reg [31:0] command=0;
  wire ready,reply,clk,byte_rst,available,clock_fault;
  wire [127:0] response;
  wire [2:0] lp_p,lp_n,hs_p,hs_n;
  dsi_image_top #(.ACTIVE_LINES(HEIGHT),.INIT_CYCLES_PER_MS(6),.J(`GOWIN_MODEL_J),.BACKLIGHT_DCS(BACKLIGHT)) dut (
    .ref_clk(ref_clk),.rst(rst),.command(command),.command_valid(valid),.command_ready(ready),
    .response(response),.response_valid(reply),.byte_clk(clk),.rst_byte(byte_rst),
    .phy_available(available),.clock_fault(clock_fault),.lp_pad_p(lp_p),.lp_pad_n(lp_n),
    .hs_pad_p(hs_p),.hs_pad_n(hs_n));
  `include "image_init_reference.vh"
  reg [127:0] result;
  task transact(input [31:0] value,input reject);
    begin
      @(negedge ref_clk);#1;command=value;valid=1;
      @(posedge ref_clk);while(!ready) @(posedge ref_clk);
      @(negedge ref_clk);#1;valid=0;
      wait(reply);#1;result=response;
      if(result[9]!==reject) $fatal(1,"image command %h status %h",value,result[31:0]);
      @(negedge ref_clk);#1;
    end
  endtask
  function [7:0] reference_ecc;
    input [23:0] h;
    begin
      // Explicit parity equations, independent of the Python syndrome lookup.
      reference_ecc[7:6]=0;
      reference_ecc[0]=h[0]^h[1]^h[2]^h[4]^h[5]^h[7]^h[10]^h[11]^h[13]^h[16]^h[20]^h[21]^h[22]^h[23];
      reference_ecc[1]=h[0]^h[1]^h[3]^h[4]^h[6]^h[8]^h[10]^h[12]^h[14]^h[17]^h[20]^h[21]^h[22]^h[23];
      reference_ecc[2]=h[0]^h[2]^h[3]^h[5]^h[6]^h[9]^h[11]^h[12]^h[15]^h[18]^h[20]^h[21]^h[22];
      reference_ecc[3]=h[1]^h[2]^h[3]^h[7]^h[8]^h[9]^h[13]^h[14]^h[15]^h[19]^h[20]^h[21]^h[23];
      reference_ecc[4]=h[4]^h[5]^h[6]^h[7]^h[8]^h[9]^h[16]^h[17]^h[18]^h[19]^h[20]^h[22]^h[23];
      reference_ecc[5]=h[10]^h[11]^h[12]^h[13]^h[14]^h[15]^h[16]^h[17]^h[18]^h[19]^h[21]^h[22]^h[23];
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

  function [7:0] rgb_ref(input integer n);
    reg [23:0] color;
    begin
      case((n/3)/90)
        0:color=24'hffffff;1:color=24'hffff00;2:color=24'h00ffff;3:color=24'h00ff00;
        4:color=24'hff00ff;5:color=24'hff0000;6:color=24'h0000ff;default:color=0;
      endcase
      rgb_ref=color>>(16-8*(n%3));
    end
  endfunction
  integer byte_cycles=0,lp_packets=0,run_count=0,run_cycles=0,b,n,packet_length,params;
  integer lp_end_cycle=0;
  reg [1:0] previous_lp=3,runs[0:260];
  reg [127:0] decoded;
  reg [15:0] lp_crc,lp_reflected;
  reg [23:0] lp_header;
  wire [1:0] lp={lp_p[0],lp_n[0]};
  always @(negedge clk) begin
    byte_cycles=byte_cycles+1;
    #0.1;
    if(rst || byte_rst || lp===2'bzz) begin previous_lp=3;run_count=0;run_cycles=0;end
    else if(!dut.lp_grant && run_count==0) begin previous_lp=3;run_cycles=0;end
    else if(lp===previous_lp) run_cycles=run_cycles+1;
    else begin
      if(previous_lp!=3 && run_cycles!=4) $fatal(1,"image LP duration %0d",run_cycles);
      if(lp==3) begin
        if(lp_packets>=INIT_COUNT) $fatal(1,"extra init packet");
        params=init_params_ref(lp_packets);
        packet_length=params<2 ? 4 : params+7;
        if(run_count!=16*(packet_length+1)+5 || runs[0]!=2 || runs[1]!=0 || runs[2]!=1 || runs[3]!=0)
          $fatal(1,"init escape %0d count %0d expected %0d",lp_packets,run_count,16*(packet_length+1)+5);
        decoded=0;
        for(b=0;b<8*(packet_length+1);b=b+1) begin
          if((runs[4+2*b]!=1 && runs[4+2*b]!=2) || runs[5+2*b]!=0) $fatal(1,"init mark/space");
          decoded[b]=(runs[4+2*b]==2);
        end
        if(decoded[7:0]!=8'h87) $fatal(1,"LP selector");
        decoded=decoded>>8;
        lp_header=decoded[23:0];
        if(decoded[31:24]!==reference_ecc(lp_header)) $fatal(1,"init ECC");
        if(params<2) begin
          if(lp_header[7:0]!=(params==0 ? 5 : 8'h15) || lp_header[15:8]!==init_payload_ref(lp_packets,0) ||
             lp_header[23:16]!==init_payload_ref(lp_packets,1)) $fatal(1,"init short payload");
        end else begin
          if(lp_header[7:0]!=8'h39 || lp_header[23:8]!=params+1) $fatal(1,"init long header");
          lp_crc=16'hffff;
          for(n=0;n<params+1;n=n+1) begin
            if(decoded[8*(4+n) +: 8]!==init_payload_ref(lp_packets,n)) $fatal(1,"init long payload");
            lp_crc=crc_msb_update(lp_crc,init_payload_ref(lp_packets,n));
          end
          lp_reflected=reflect16(lp_crc);
          if(decoded[8*(params+5) +: 16]!==lp_reflected) $fatal(1,"init CRC");
        end
        lp_packets=lp_packets+1;run_count=0;lp_end_cycle=byte_cycles;
      end else begin
        if(run_count==0 && lp_packets>0 && byte_cycles-lp_end_cycle<6*init_delay_ref(lp_packets-1))
          $fatal(1,"init wait too short");
        if(run_count>=261) $fatal(1,"init phase overflow");
        runs[run_count]=lp;run_count=run_count+1;
      end
      previous_lp=lp;run_cycles=1;
    end
    if(dut.lp_grant && hs_p!==3'bzzz) $fatal(1,"image LP/HS overlap");
  end

  integer line=0,serial_lines=0,serial_frames=0,serial_index=0,serial_bits=0;
  integer packet_offset,payload_length,local_index;
  reg [7:0] shift0=0,shift1=0,expected,dt;
  reg [23:0] header;
  reg [31:0] header_ecc;
  reg [15:0] crc=16'hffff,reflected;
  reg synced=0,active,allow_abort=0;
  wire serial_clock=hs_p[2]===1'b1;
  wire data_active=hs_p[0]!==1'bz;
  task consume(input [7:0] value);
    begin
      active=line>=8 && line<8+HEIGHT;
      if(serial_index<4) begin packet_offset=0;payload_length=-1;dt=line==0 ? 1 : line==5 ? 8'h11 : 8'h21;end
      else if(serial_index<8) begin packet_offset=4;payload_length=-1;dt=8'h31;end
      else if(serial_index<86) begin packet_offset=8;payload_length=72;dt=8'h19;end
      else if(serial_index<2252) begin packet_offset=86;payload_length=2160;dt=active ? 8'h3e : 8'h19;end
      else if(serial_index<2322) begin packet_offset=2252;payload_length=64;dt=8'h19;end
      else begin packet_offset=2322;payload_length=-1;dt=8'h08;end
      local_index=serial_index-packet_offset;
      header=payload_length<0 ? {16'd0,dt} : {16'(payload_length),dt};
      if(dt==8'h08) header={16'h0f0f,dt};
      header_ecc={reference_ecc(header),header};
      if(local_index==0) crc=16'hffff;
      if(local_index<4) expected=header_ecc[8*local_index +: 8];
      else if(local_index<4+payload_length) begin
        expected=(packet_offset==86 && active) ? rgb_ref(local_index-4) : 0;
        crc=crc_msb_update(crc,expected);
      end else begin
        reflected=reflect16(crc);
        expected=local_index==4+payload_length ? reflected[7:0] : reflected[15:8];
      end
      if(value!==expected) $fatal(1,"image serial line %0d byte %0d got %h expected %h",line,serial_index,value,expected);
      serial_index=serial_index+1;
      if(serial_index==2326) begin
        serial_lines=serial_lines+1;
        if(line==TOTAL-1) begin line=0;serial_frames=serial_frames+1;end
        else line=line+1;
      end
    end
  endtask
  always @(posedge serial_clock or negedge serial_clock) begin
    if(!rst && !byte_rst && data_active) begin
      if(lp_packets!=INIT_COUNT) $fatal(1,"video before initialization");
      if(byte_cycles-lp_end_cycle<6*init_delay_ref(INIT_COUNT-1)) $fatal(1,"final init wait too short");
      shift0={hs_p[0],shift0[7:1]};shift1={hs_p[1],shift1[7:1]};
      if(!synced) begin
        if(shift0==8'hb8 && shift1==8'hb8) begin synced=1;serial_bits=0;serial_index=0;end
      end else if(serial_index<2326) begin
        serial_bits=serial_bits+1;
        if(serial_bits==8) begin consume(shift0);consume(shift1);serial_bits=0;end
      end
    end
  end
  always @(negedge data_active or posedge rst or posedge byte_rst) begin
    #0.0005;
    if(!rst && !byte_rst && !allow_abort && synced && serial_index!=2326) $fatal(1,"image truncated burst");
    synced=0;serial_bits=0;shift0=0;shift1=0;
  end
  integer previous_request=0,delta,periods=0;
  always @(posedge clk) if(rst || byte_rst || dut.stopped) previous_request=0;
  else if(dut.hs_req && dut.hs_req_ready) begin
    if(previous_request!=0) begin
      delta=byte_cycles-previous_request;
      if(delta!=1333 && delta!=1334) $fatal(1,"line period %0d",delta);
      periods=periods+1;
    end
    previous_request=byte_cycles;
  end
  initial begin
    repeat(5) @(negedge ref_clk);#1;rst=0;
    wait(serial_frames>=2);
    transact(6,0);
    while(!result[1]) transact(0,0);
    if(result[4] || result[95:64]!=INIT_COUNT || result[63:32]!=serial_frames || periods<2*TOTAL-1 ||
       !result[30] || result[25]!==BACKLIGHT[0] || result[24:21]!=INIT_COUNT-1)
      $fatal(1,"image accounting flags=%h lp=%d frames=%d serial=%d",result[31:0],result[95:64],result[63:32],serial_frames);
    previous_request=0;
    transact(5,0);transact(6,0);
    while(!result[1]) transact(0,0);
    if(result[4] || result[63:32]!=serial_frames) $fatal(1,"image restart");
    // Active PLL loss must immediately inhibit all pads, including stopped PCLK.
    transact(5,0);wait(data_active);allow_abort=1;
    @(negedge ref_clk);#1;dut.wrapper.clocks.pll0.locked=0;dut.wrapper.clocks.pll0.halted=1;
    #0.01;
    if(!clock_fault || !byte_rst || {lp_p,lp_n,hs_p,hs_n}!==12'bzzzzzzzzzzzz) $fatal(1,"image PLL fault mask");
    $display("PASS image pads J=%0d BL=%0d: %0d DCS init packets incl long/ECC/CRC, active RGB888+HSS/HSE/VSS/VSE/blanking/EoTp, 45kHz lines, STOP/restart, diagnostic flags, PLL inhibition",`GOWIN_MODEL_J,BACKLIGHT,INIT_COUNT);
    $finish;
  end
  initial begin #6000000;$fatal(1,"image timeout state=%0d cause=%0d step=%d line=%d",dut.source.state,dut.source.error_cause,dut.source.init_index,dut.source.line_index);end
endmodule
