`timescale 1ns/1ps
module display_lp_board_TB;
  reg clk=0,rst=1,valid=0;
  always #12.5 clk=~clk;
  reg [31:0] command=0;
  wire ready,reply,available;
  wire [127:0] response;
  wire [2:0] lp_p,lp_n,hs_p,hs_n;
  dsi_display_top #(.LP_ONLY(1),.PROFILE_OK(1)) dut (
    .ref_clk(clk),.rst(rst),.command(command),.command_valid(valid),.command_ready(ready),
    .response(response),.response_valid(reply),.byte_clk(),.rst_byte(),
    .phy_available(available),.clock_fault(),.lp_pad_p(lp_p),.lp_pad_n(lp_n),
    .hs_pad_p(hs_p),.hs_pad_n(hs_n));
  wire [2:0] parked_p,parked_n,parked_hs_p,parked_hs_n;
  dsi_display_top #(.LP_ONLY(1),.PROFILE_OK(0)) parked (
    .ref_clk(clk),.rst(rst),.command(32'd7),.command_valid(1'b1),.command_ready(),
    .response(),.response_valid(),.byte_clk(),.rst_byte(),.phy_available(),.clock_fault(),
    .lp_pad_p(parked_p),.lp_pad_n(parked_n),.hs_pad_p(parked_hs_p),.hs_pad_n(parked_hs_n));
  reg [127:0] result;
  task transact(input [31:0] word,input rejected);
    begin
      @(negedge clk);#1;command=word;valid=1;
      @(posedge clk);while(!ready) @(posedge clk);
      @(negedge clk);#1;valid=0;
      wait(reply);#1;result=response;
      if(result[9]!==rejected) $fatal(1,"LP board command %h flags=%h",word,result[31:0]);
      @(negedge clk);#1;
    end
  endtask
  wire [1:0] lp={lp_p[0],lp_n[0]};
  reg [1:0] previous=3,runs[0:84];
  reg [39:0] decoded;
  integer count=0,cycles=0,b,packets=0;
  always @(negedge clk) begin
    #0.1;
    if(hs_p!==3'bzzz || hs_n!==3'bzzz) $fatal(1,"LP board drove HS");
    if({parked_p,parked_n,parked_hs_p,parked_hs_n}!==12'bzzzzzzzzzzzz)
      $fatal(1,"parked board drove pads");
    if(rst || !available || lp===2'bzz) begin previous=3;count=0;cycles=0;end
    else begin
      if({lp_p[2:1],lp_n[2:1]}!==4'b1111) $fatal(1,"LP board changed CLK/D1");
      if(lp===previous) cycles=cycles+1;
      else begin
        if(previous!=3 && cycles!=4) $fatal(1,"LP duration %d",cycles);
        if(lp==3) begin
          if(count!=85 || runs[0]!=2 || runs[1]!=0 || runs[2]!=1 || runs[3]!=0 || runs[84]!=2)
            $fatal(1,"LP escape");
          decoded=0;
          for(b=0;b<40;b=b+1) begin
            if((runs[4+2*b]!=1 && runs[4+2*b]!=2) || runs[5+2*b]!=0) $fatal(1,"LP mark/space");
            decoded[b]=(runs[4+2*b]==2);
          end
          if(decoded!==40'h1000010587) $fatal(1,"LP command %h",decoded);
          packets=packets+1;count=0;
        end else begin
          if(count>=85) $fatal(1,"extra LP phase");
          runs[count]=lp;count=count+1;
        end
        previous=lp;cycles=1;
      end
    end
  end
  initial begin
    repeat(5) @(negedge clk);#1;rst=0;
    repeat(4100) @(negedge clk);
    transact(5,1);transact(2,1);
    transact(32'h17,0);
    transact(5,1);
    while(result[95:64]!=1) transact(0,0);
    if(packets!=1 || result[4]) $fatal(1,"LP board completion");
    transact(1,0);transact(3,0);transact(5,1); // No configuration can unlock HS.
    @(negedge clk);#1;rst=1;
    #0.1;
    if({lp_p,lp_n,hs_p,hs_n}!==12'bzzzzzzzzzzzz) $fatal(1,"board reset pads");
    repeat(5) @(negedge clk);#1;rst=0;
    repeat(4100) @(negedge clk);
    transact(32'h17,0);
    while(result[95:64]!=1) transact(0,0);
    if(packets!=2) $fatal(1,"board reset recovery");
    $display("PASS LP board: 40MHz direct clock, DCS decoded at pads, 4-cycle phases, CLK/D1 LP11, HS always Z, parked/reset and START/APPLY rejection");
    $finish;
  end
  initial begin #1000000;$fatal(1,"LP board timeout");end
endmodule
