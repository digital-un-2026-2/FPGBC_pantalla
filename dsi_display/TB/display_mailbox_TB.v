`timescale 1ns/1ps
module display_mailbox_TB;
  reg ref_clk=0,byte_clk=0,ref_rst=1,byte_rst=1,valid=0;
  // Unrelated clocks, deliberately neither phase nor frequency locked.
  always #7 ref_clk=~ref_clk;
  always #12.5 byte_clk=~byte_clk;
  reg [31:0] command=0;
  wire ready,reply,byte_valid;
  wire [31:0] byte_command;
  wire [127:0] response;
  reg response_valid=0;
  reg [127:0] byte_response=0;
  reg [3:0] delay_count=0;
  reg [31:0] saved=0;
  integer accepted=0,completed=0,n;
  display_mailbox dut (
    .ref_clk(ref_clk),.ref_rst(ref_rst),.byte_clk(byte_clk),.byte_rst(byte_rst),
    .command(command),.command_valid(valid),.command_ready(ready),.response(response),.response_valid(reply),
    .byte_command(byte_command),.byte_valid(byte_valid),.byte_ready(1'b1),
    .byte_response(byte_response),.byte_response_valid(response_valid));
  always @(posedge byte_clk or posedge byte_rst) begin
    if(byte_rst) begin delay_count<=0;response_valid<=0;end
    else begin
      response_valid<=0;
      if(byte_valid) begin
        if(delay_count) $fatal(1,"duplicate destination request");
        saved<=byte_command;delay_count<=5;accepted=accepted+1;
      end else if(delay_count) begin
        delay_count<=delay_count-1;
        if(delay_count==1) begin byte_response<={4{saved}};response_valid<=1;end
      end
    end
  end
  task send(input [31:0] value);
    begin
      @(negedge ref_clk);command=value;valid=1;
      @(posedge ref_clk);while(!ready) @(posedge ref_clk);
      @(negedge ref_clk);valid=0;command=~value;
    end
  endtask
  initial begin
    #51;ref_rst=0;byte_rst=0;
    for(n=0;n<100;n=n+1) begin
      send(32'hc5a00000+n);
      wait(reply);#1;
      if(response!=={4{32'hc5a00000+n}}) $fatal(1,"torn mailbox response");
      completed=completed+1;
      @(negedge ref_clk);
    end
    send(32'hdeadbeef);wait(byte_valid);#1;ref_rst=1;byte_rst=1;
    #61;ref_rst=0;byte_rst=0;
    repeat(20) @(negedge ref_clk);
    if(reply || !ready) $fatal(1,"reset replay");
    send(32'h12345678);wait(reply);#1;
    if(response!=={4{32'h12345678}}) $fatal(1,"reset recovery");
    $display("PASS mailbox: 100 unrelated-clock transactions, coherent snapshots, reset in flight, recovery");
    $finish;
  end
  initial begin #200000;$fatal(1,"mailbox timeout");end
endmodule
