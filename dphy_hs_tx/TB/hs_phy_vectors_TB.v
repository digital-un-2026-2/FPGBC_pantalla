`timescale 1ns/1ps
module hs_phy_vectors_TB;
  reg clk=0;
  always #12.5 clk=~clk;
  reg [26:0] inputs=0;
  wire [35:0] observed;
  wire [15:0] frame_data;
  wire [1:0] kind, lc, ld0, ld1;
  wire cp, dp, ds, cs, stop, error, hd, hc, toggle;
  wire [2:0] code;
  dphy_hs_tx dut(.clk(clk),.rst(inputs[26]),.phy_abort(inputs[25]),
    .clk_start_req(inputs[24]),.data_start_req(inputs[23]),
    .data_stop_req(inputs[22]),.clk_stop_req(inputs[21]),.hs_grant(inputs[20]),
    .hs_word_valid(inputs[19]),.hs_word_last(inputs[18]),.hs_word_keep(inputs[17:16]),
    .hs_word_data(inputs[15:0]),.clk_prepared(cp),.data_prepared(dp),
    .data_stopped(ds),.clk_stopped(cs),.hs_local_stop(stop),.phy_error(error),
    .error_code(code),.hs_frame_data(frame_data),.hs_frame_kind(kind),
    .hs_data_on(hd),.hs_clk_on(hc),.clk_toggle(toggle),.lp_clk(lc),.lp_d0(ld0),.lp_d1(ld1));
  assign observed={lc,ld0,ld1,code,toggle,hc,hd,error,stop,cs,ds,dp,cp,kind,frame_data};
  integer f,rc,count=0;
  reg [26:0] next_inputs;
  reg [35:0] expected;
  reg [1023:0] path;
  initial begin
    if(!$value$plusargs("vectors=%s",path)) $fatal(1,"missing vectors");
    f=$fopen(path,"r"); if(!f) $fatal(1,"open vectors");
    while(!$feof(f)) begin
      rc=$fscanf(f,"%h %h\n",next_inputs,expected);
      if(rc!=2) $fatal(1,"malformed vector");
      @(negedge clk); inputs=next_inputs;
      #1;
      if((inputs[26]||inputs[25]) && (cp||dp||ds||cs||hd||hc||toggle))
        $fatal(1,"asynchronous reset/abort mask");
      @(posedge clk); #1;
      if(observed!==expected)
        $fatal(1,"vector %0d input=%h observed=%h expected=%h state=%d",count,inputs,observed,expected,dut.control.state);
      count=count+1;
    end
    $fclose(f);
    $display("PASS: %0d public-interface reference cycles",count); $finish;
  end
  initial begin #20000000; $fatal(1,"watchdog"); end
endmodule
