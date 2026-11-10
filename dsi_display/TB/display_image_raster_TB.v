`timescale 1ns/1ps

// Full 720-row raster with a consuming PHY surrogate. The serial/LP encodings
// are checked separately by display_image_TB with the real PHY and pad models.
module display_image_raster_TB;
  reg clk=0, rst=1, start=0, stop=0, block_requests=0;
  always #5 clk=~clk;
  wire lp_req, lp_done, hs_req, hs_done, valid, last, running, stopped, error;
  wire [15:0] word;
  wire [31:0] frames, lp_count;
  wire [3:0] cause;
  wire [9:0] line;
  reg lp_grant=0, lp_complete=0, hs_grant=0, hs_complete=0;
  reg [3:0] completion_delay=0;
  wire ready=!block_requests && !hs_grant && completion_delay==0;
  display_image_control #(.INIT_CYCLES_PER_MS(1)) dut (
    .clk(clk),.rst(rst),.phy_ready(1'b1),.stop_ready(1'b1),.external_error(1'b0),
    .start(start),.stop(stop),.lp_req(lp_req),.lp_grant(lp_grant),
    .lp_complete(lp_complete),.lp_done(lp_done),.estado_D0(),
    .hs_req(hs_req),.hs_req_ready(ready),.hs_grant(hs_grant),.hs_complete(hs_complete),
    .hs_data_ready(),.hs_done(hs_done),.hs_word(word),.hs_valid(valid),.hs_last(last),
    .initialized(),.running(running),.stopped(stopped),.error(error),.error_cause(cause),
    .frames(frames),.lp_count(lp_count),.init_step(),.raster_line(line));

  integer cycles=0, first_frame_cycle=0, previous_request=0;
  integer requests=0, complete_lines=0, active_rows=0, words=0;
  always @(posedge clk) begin
    cycles=cycles+1;
    lp_complete<=0; hs_complete<=0;
    if(rst) begin
      lp_grant<=0;hs_grant<=0;completion_delay<=0;
    end else begin
      if(lp_req) lp_grant<=1;
      if(lp_done) begin lp_grant<=0;lp_complete<=1;end
      if(hs_req && ready) begin
        if(line !== requests%750) $fatal(1,"Raster line order %d after %d requests",line,requests);
        if(requests==0) first_frame_cycle=cycles;
        else if(requests==750 && cycles-first_frame_cycle!=1000000)
          $fatal(1,"60Hz frame requires exactly 1,000,000 byte cycles: %d",cycles-first_frame_cycle);
        if(previous_request!=0 && !stopped && requests<1500 &&
            cycles-previous_request!=1333 && cycles-previous_request!=1334)
          $fatal(1,"45kHz line interval %d",cycles-previous_request);
        previous_request=cycles; requests=requests+1;
        hs_grant<=1; words=0;
      end
      if(valid) begin
        if(words==43) begin
          if(line>=8 && line<728) begin
            if(word[7:0]!==8'h3e) $fatal(1,"Missing RGB888 row %d",line);
            active_rows=active_rows+1;
          end else if(word[7:0]!==8'h19) $fatal(1,"Pixel packet in vertical blank %d",line);
        end
        if(last !== (words==1162)) $fatal(1,"Incorrect last at word %d",words);
        words=words+1;
      end
      if(hs_done) begin
        if(words!=1163) $fatal(1,"Line length %d",words);
        complete_lines=complete_lines+1;
        hs_grant<=0;completion_delay<=6;
      end
      if(completion_delay!=0) begin
        completion_delay<=completion_delay-1;
        if(completion_delay==1) hs_complete<=1;
      end
    end
  end
  initial begin
    repeat(5) @(negedge clk);rst=0;
    wait(frames==1);wait(line==1);@(negedge clk);stop=1;
    @(negedge clk);stop=0;
    wait(stopped);@(negedge clk);
    if(error || frames!=2 || lp_count!=11 || requests!=1500 ||
        complete_lines!=1500 || active_rows!=1440)
      $fatal(1,"Full raster: frames=%d LP=%d requests=%d lines=%d RGB=%d error=%b",
          frames,lp_count,requests,complete_lines,active_rows,error);
    repeat(3000) @(negedge clk);
    if(requests!=1500) $fatal(1,"STOP emitted more lines");
    block_requests=1;start=1;@(negedge clk);start=0;
    wait(error);@(negedge clk);
    if(cause!=4 || running) $fatal(1,"Missed line deadline must halt with overrun cause");
    $display("PASS full image raster: 750 lines/frame, 720 RGB rows, exactly 60Hz/45kHz, two frames, STOP and overrun");
    $finish;
  end
  initial begin #25000000;$fatal(1,"Full raster timeout");end
endmodule
