`timescale 1ns/1ps
`include "csr_addresses.vh"
module display_csr_TB;
  reg clk=0,rst=1,we=0,re=0;
  reg [13:0] adr=0;
  reg [31:0] data=0;
  wire [31:0] read_data;
  always #12.5 clk=~clk;
  display_csr dut(.sys_clk(clk),.sys_rst(rst),.csr_we(we),.csr_re(re),
    .csr_adr(adr),.csr_dat_w(data),.csr_dat_r(read_data));
  task write(input [13:0] address,input [31:0] value);
    begin
      @(negedge clk);adr=address;data=value;we=1;
      @(negedge clk);we=0;
    end
  endtask
  task read(input [13:0] address,output [31:0] value);
    begin
      @(negedge clk);adr=address;re=1;
      repeat(2) @(negedge clk);
      value=read_data;re=0;
    end
  endtask
  reg [31:0] bridge,flags,sequence_value,previous_sequence,frames,count;
  task transact(input [31:0] word,input rejected);
    begin
      read(`CSR_BRIDGE,bridge);
      while(!bridge[0]) read(`CSR_BRIDGE,bridge);
      read(`CSR_SEQUENCE,previous_sequence);
      write(`CSR_COMMAND,word);
      read(`CSR_BRIDGE,bridge);
      while(!bridge[1]) read(`CSR_BRIDGE,bridge);
      read(`CSR_SEQUENCE,sequence_value);
      read(`CSR_FLAGS,flags);
      if(sequence_value!=previous_sequence+1 || flags[9]!==rejected)
        $fatal(1,"CSR command/result %h seq=%d old=%d flags=%h",word,sequence_value,previous_sequence,flags);
    end
  endtask
  initial begin
    repeat(6) @(negedge clk);rst=0;
    read(`CSR_RESET,count);
    if(count!=1) $fatal(1,"reset must default asserted");
    write(`CSR_COMMAND,5);read(`CSR_BRIDGE,bridge);
    if(bridge[0] || bridge[6]) $fatal(1,"command accepted under reset");
    write(`CSR_RESET,0);
    repeat(4100) @(negedge clk);
    transact(5,1);
    transact(32'h17,0);
    count=0;
    while(count==0) begin transact(0,0);read(`CSR_LP_COMPLETED,count);end
    transact(1,0);transact(2,0);transact(3,0);transact(5,0);
    transact(7,1);transact(6,0);
    while(!flags[1]) transact(0,0);
    read(`CSR_FRAMES,frames);
    if(frames!=1 || flags[4]) $fatal(1,"CSR frame/STOP result");
    // Consecutive writes: the second cannot overwrite an in-flight mailbox.
    write(`CSR_COMMAND,0);write(`CSR_COMMAND,15);
    repeat(30) @(negedge clk);
    read(`CSR_BRIDGE,bridge);
    if(!bridge[2] || !bridge[1]) $fatal(1,"busy CSR write was not reported");
    write(`CSR_CLEAR,1);read(`CSR_BRIDGE,bridge);
    if(bridge[2]) $fatal(1,"sticky CSR reject clear");
    read(`CSR_FLAGS,flags);
    if(flags[9]) $fatal(1,"busy command overwrote accepted snapshot");
    write(`CSR_COMMAND,0);write(`CSR_RESET,1);
    repeat(10) @(negedge clk);
    read(`CSR_SEQUENCE,sequence_value);read(`CSR_BRIDGE,bridge);
    if(sequence_value || bridge[1] || bridge[6]) $fatal(1,"reset retained stale reply");
    write(`CSR_RESET,0);repeat(4100) @(negedge clk);
    transact(0,0);read(`CSR_FRAMES,frames);
    if(frames || flags[3] || flags[2]) $fatal(1,"CSR reset/recovery");
    $display("PASS LiteX CSR: real generated adapter/bank, LP completion, frame/STOP, busy reject, coherent snapshot and reset recovery");
    $finish;
  end
  initial begin #2000000;$fatal(1,"CSR timeout");end
endmodule
