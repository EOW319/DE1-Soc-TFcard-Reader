`timescale 1ns/1ps

module tb_sdcmd_ctrl;

  // ============================================================
  // 1) clock / reset (system clk, not sdclk)
  // ============================================================
  logic clk;
  logic rstn;

  localparam time TCLK = 20ns; // 50MHz
  initial clk = 1'b0;
  always #(TCLK/2) clk = ~clk;

  // ============================================================
  // 2) DUT-side control/status
  // ============================================================
  logic        start;
  logic [15:0] clkdiv;
  logic [15:0] precnt;
  logic [5:0]  cmd;
  logic [31:0] arg;

  logic        busy;
  logic        done;
  logic        timeout;
  logic        syntaxe;
  logic [31:0] resparg;

  // ============================================================
  // 3) SD interface
  // ============================================================
  logic sdclk;

  // CMD bus: must be a net for multi-driver resolution
  tri  sdcmd;
  pullup(sdcmd);

  // TB(card) driver onto CMD line
  logic card_oe;
  logic card_out;
  assign sdcmd = card_oe ? card_out : 1'bz;

  // DUT(host) output enable (exported by DUT)
  logic sdcmdoe;

  // ============================================================
  // 4) DUT instantiation (matches your interface)
  // ============================================================
  sdcmd_ctrl DUT (
    .rstn     (rstn),
    .clk      (clk),
    .sdclk    (sdclk),
    .sdcmd    (sdcmd),
    .clkdiv   (clkdiv),
    .start    (start),
    .precnt   (precnt),
    .cmd      (cmd),
    .arg      (arg),
    .busy     (busy),
    .done     (done),
    .timeout  (timeout),
    .syntaxe  (syntaxe),
    .resparg  (resparg),
    .sdcmdoe  (sdcmdoe)
  );

  // ============================================================
  // 5) CRC7 (poly x^7 + x^3 + 1 => 0x09), MSB-first
  //    For 48-bit frame: CRC over bits[47:8] (40 bits)
  // ============================================================
  function automatic logic [6:0] crc7_msb_first(input logic [39:0] data);
    logic [6:0] crc;
    int i;
    begin
      crc = 7'd0;
      for (i = 39; i >= 0; i--) begin
        if (data[i] ^ crc[6])
          crc = {crc[5:0], 1'b0} ^ 7'h09;
        else
          crc = {crc[5:0], 1'b0};
      end
      return crc;
    end
  endfunction

  // ============================================================
  // 6) Basic helpers
  // ============================================================
  task automatic reset_dut();
    begin
      rstn     = 1'b0;
      start    = 1'b0;
      clkdiv   = 16'd100;   // default
      precnt   = 16'd74;    // default
      cmd      = '0;
      arg      = '0;

      card_oe  = 1'b0;
      card_out = 1'b1;

      repeat (5) @(posedge clk);
      rstn = 1'b1;
      repeat (5) @(posedge clk);
    end
  endtask

  task automatic start_cmd(
    input logic [5:0]  cmd_idx,
    input logic [31:0] cmd_arg,
    input logic [15:0] clkdiv_num,
    input logic [15:0] precnt_num
  );
    begin
      if(busy)begin
        $stop;
        $error("Can't give cmd to ctrl when it's busy");
      end
      @(posedge clk);
      precnt <= precnt_num;
      clkdiv <= clkdiv_num;
      cmd    <= cmd_idx;
      arg    <= cmd_arg;
      start  <= 1'b1;
      @(posedge clk);
      start  <= 1'b0;
    end
  endtask

  // ============================================================
  // 7) Observe host (DUT) command frame on CMD line
  //    We use sdcmdoe to know host is driving.
  // ============================================================
  task automatic wait_host_startbit();
    begin
      // host starts driving
      wait (sdcmdoe == 1'b1);
      // wait until start bit appears low on the line
      // sample around sdclk edges for stability
      wait (sdcmd == 1'b0);
    end
  endtask

  task automatic wait_host_release();
    begin
      wait (sdcmdoe == 1'b0);
      @(posedge sdclk);
    end
  endtask

  task automatic wait_host_acquire();
    begin
      wait (sdcmdoe == 1'b1);
      @(posedge sdclk);
    end
  endtask

  // Capture 48-bit host command (MSB-first), sampled on posedge sdclk
  task automatic capture_cmd48(output logic [47:0] frame);
    int i;
    begin
      wait_host_startbit();
      for (i = 47; i >= 0; i--) begin
        @(posedge sdclk);
        frame[i] = sdcmd;
      end
    end
  endtask

  // Check that the command frame matches expected cmd/arg and CRC
  task automatic check_cmd48(
    input logic [47:0] frame,
    input logic [5:0]  exp_cmd,
    input logic [31:0] exp_arg
  );
    logic [39:0] crc_data;
    logic [6:0]  crc_calc;
    begin
      // CMD frame format:
      // [47] start=0
      // [46] transmission=1 (host)
      // [45:40] cmd index
      // [39:8] arg
      // [7:1] crc7
      // [0] end=1
      $display("\n");
      $display("---------Check begin, all errors are displayed below--------");
      if (frame[47] !== 1'b0) $error("CMD start wrong: %b", frame[47]);
      if (frame[46] !== 1'b1) $error("CMD trans wrong (host should be 1): %b", frame[46]);
      if (frame[45:40] !== exp_cmd) $error("CMD idx wrong: got %0d exp %0d", frame[45:40], exp_cmd);
      if (frame[39:8]  !== exp_arg) $error("CMD arg wrong: got %08h exp %08h", frame[39:8], exp_arg);
      if (frame[0]     !== 1'b1) $error("CMD end wrong: %b", frame[0]);

      crc_data = frame[47:8];
      crc_calc = crc7_msb_first(crc_data);
      if (frame[7:1] !== crc_calc)
        $error("CMD CRC wrong: got %02h exp %02h", frame[7:1], crc_calc);
      $display("---------Check done, all errors are displayed above---------\n");
    end
  endtask

  // ============================================================
  // 8) Card model: Drive 48-bit R1 response
  //    Wait host release, then Ncr cycles, then drive response.
  //    Update on negedge sdclk for setup before posedge sampling.
  // ============================================================
  task automatic drive_r1(
    input logic [5:0]  r_cmd_idx,
    input logic [31:0] card_status,
    input int          ncr_cycles = 74
  );
    logic [47:0] r;
    logic [39:0] crc_data;
    logic [6:0]  c;
    int b;

    begin
      wait_host_acquire();
      wait_host_release();
      repeat (ncr_cycles) @(posedge sdclk);

      r[47]    = 1'b0;          // start
      r[46]    = 1'b0;          // transmission (card)
      r[45:40] = r_cmd_idx;
      r[39:8]  = card_status;
      r[7:1]   = 7'd0;
      r[0]     = 1'b1;          // end

      crc_data = r[47:8];
      c        = crc7_msb_first(crc_data);
      r[7:1]   = c;
      card_oe = 1'b1;
      for (b = 47; b >= 0; b--) begin
        @(negedge sdclk);
        card_out = r[b];
      end
      @(negedge sdclk);
      card_out = 1'b1;
      card_oe  = 1'b0;
    end
  endtask

  // ============================================================
  // 9) Tests
  // ============================================================
  initial begin
    logic [47:0] frame;

    $timeformat(-9, 1, " ns", 8);

    reset_dut();

    // -------------------------
    // Test 1: CMD8 send + verify
    // -------------------------
    $display("[%0t] TEST1: Send CMD8 and verify 48-bit frame", $time);

    start_cmd(6'd8, 32'h0000_01AA, 16'd100, 16'd74);
    fork
      begin
        capture_cmd48(frame);
        $display("[%0t] Captured CMD = 0x%012h", $time, frame);
        check_cmd48(frame, 6'd8, 32'h0000_01AA);
      end
    join_none

    wait (done || timeout);
    @(posedge clk);

    $display("[%0t] done=%0d timeout=%0d syntaxe=%0d resparg=%08h",
             $time, done, timeout, syntaxe, resparg);
    // If your DUT sets done even without response, this will finish.
    // Otherwise it may wait for response -> use Test2 below.
    // -------------------------
    // Test 2: CMD8 send + card R1 response
    // -------------------------
    $display("[%0t] TEST2: Send CMD8, then drive R1 response", $time);

    fork
      begin
        capture_cmd48(frame);
        check_cmd48(frame, 6'd8, 32'h0000_01AA);
      end
      begin
        // card responds after Ncr cycles
        drive_r1(6'd8, 32'h0000_2000, precnt);
      end
    join_none

    start_cmd(6'd8, 32'h0000_01AA, 16'd100, 16'd74);

    // wait end condition
    @(posedge clk);
    wait (done || timeout || syntaxe);
    @(posedge clk);
    if (done == 1 && resparg ==32'h0000_2000) begin
      $display("response is correct");
    end
    else begin
      $error("[%0t] done=%0d timeout=%0d syntaxe=%0d resparg=%08h",
             $time, done, timeout, syntaxe, resparg);
    end

    repeat (50) @(posedge clk);
    $stop;
  end

endmodule
