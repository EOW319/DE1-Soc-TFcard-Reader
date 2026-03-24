// =============================================================================
// vga_tests.sv
// VGA 控制器独立验证测试用例
//
// vga_base_test     — 基础 test，预加载 img_ram，实例化 vga_ctrl
// vga_timing_test   — VGA 时序参数验证
// vga_pixel_test    — RGB332→RGB888 像素映射验证
// vga_fullframe_test — 全帧扫描连续验证 (≥2 帧)
// =============================================================================
`ifndef VGA_TESTS_SV
`define VGA_TESTS_SV

// -----------------------------------------------------------------------------
// VGA 时序期望参数 (640×480@60Hz)
// H_TOTAL    = 800,  H_VISIBLE = 640
// H_FRONT    = 16,   H_SYNC    = 96,   H_BACK = 48
// V_TOTAL    = 525,  V_VISIBLE = 480
// V_FRONT    = 10,   V_SYNC    = 2,    V_BACK = 33
// PIXEL_CLK  = 25 MHz

// 时序常量 (用于 test 内检查，与 vga_monitor 中一致)
localparam int VGA_H_VISIBLE = 640;
localparam int VGA_H_FRONT   = 16;
localparam int VGA_H_SYNC    = 96;
localparam int VGA_H_BACK    = 48;
localparam int VGA_H_TOTAL   = VGA_H_VISIBLE + VGA_H_FRONT + VGA_H_SYNC + VGA_H_BACK;

localparam int VGA_V_VISIBLE = 480;
localparam int VGA_V_FRONT   = 10;
localparam int VGA_V_SYNC    = 2;
localparam int VGA_V_BACK    = 33;
localparam int VGA_V_TOTAL   = VGA_V_VISIBLE + VGA_V_FRONT + VGA_V_SYNC + VGA_V_BACK;

// -----------------------------------------------------------------------------
// 基础 Test
// -----------------------------------------------------------------------------
class vga_base_test extends uvm_test;
    `uvm_component_utils(vga_base_test)

    // img_ram 预加载数据 (待写入 DUT 的 img_ram)
    byte unsigned test_image[76800];  // 320×240 测试图案
    virtual sd_sys_if.vga_mon vif_vga;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual sd_sys_if.vga_mon)::get(this, "", "vif_vga", vif_vga))
            `uvm_fatal("VGA_TEST", "Failed to get vif_vga")

        // 生成测试图案:
        //   - 渐变色: test_image[i] = i % 256
        //   - 棋盘格: test_image[i] = ((i/320 + i%320) % 2) ? 8'hFF : 8'h00
        foreach (test_image[i])
            test_image[i] = i % 256;  // 默认: 渐变色
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_test_body(phase);
        phase.drop_objection(this);
    endtask

    virtual task run_test_body(uvm_phase phase);
    endtask

    task wait_until_ready();
        wait (vif_vga.rst_n === 1'b1);
        wait (vif_vga.preload_done === 1'b1);
        repeat (4) @(posedge vif_vga.vga_clk);
    endtask

    task wait_visible_frame_start();
        wait_until_ready();

        @(negedge vif_vga.vga_vs);
        @(posedge vif_vga.vga_vs);

        forever begin
            @(posedge vif_vga.vga_clk);
            if (vif_vga.vga_blank_n)
                break;
        end
    endtask

    task advance_clocks(input int num_clocks);
        repeat (num_clocks) @(posedge vif_vga.vga_clk);
    endtask

    function automatic byte unsigned rgb888_to_rgb332(
        input logic [7:0] r8,
        input logic [7:0] g8,
        input logic [7:0] b8
    );
        return {r8[7:5], g8[7:5], b8[7:6]};
    endfunction

    function automatic void ref_rgb332_to_888(
        input  byte unsigned rgb332,
        output byte unsigned r8,
        output byte unsigned g8,
        output byte unsigned b8
    );
        r8 = {rgb332[7:5], rgb332[7:5], rgb332[7:6]};
        g8 = {rgb332[4:2], rgb332[4:2], rgb332[4:3]};
        b8 = {rgb332[1:0], rgb332[1:0], rgb332[1:0], rgb332[1:0]};
    endfunction

    task sample_visible_pixel(
        input  int x,
        input  int y,
        output byte unsigned got_r,
        output byte unsigned got_g,
        output byte unsigned got_b,
        output logic        got_blank_n
    );
        wait_visible_frame_start();
        advance_clocks(y * VGA_H_TOTAL + x);

        got_r       = vif_vga.vga_r;
        got_g       = vif_vga.vga_g;
        got_b       = vif_vga.vga_b;
        got_blank_n = vif_vga.vga_blank_n;
    endtask

    task capture_frame(output byte unsigned frame_pixels[76800]);
        int px;

        foreach (frame_pixels[i])
            frame_pixels[i] = 8'h00;

        wait_visible_frame_start();

        for (int row = 0; row < VGA_V_VISIBLE; row++) begin
            for (int col = 0; col < VGA_H_TOTAL; col++) begin
                if (col < VGA_H_VISIBLE) begin
                    if (!vif_vga.vga_blank_n)
                        `uvm_error("VGA_FRAME", $sformatf("blank_n deasserted inside visible area at (%0d,%0d)", col, row))

                    if (col[0] == 0 && row[0] == 0) begin
                        px = (row >> 1) * 320 + (col >> 1);
                        frame_pixels[px] = rgb888_to_rgb332(vif_vga.vga_r, vif_vga.vga_g, vif_vga.vga_b);
                    end
                end else if (vif_vga.vga_blank_n) begin
                    `uvm_error("VGA_FRAME", $sformatf("blank_n asserted in horizontal blanking at row=%0d col=%0d", row, col))
                end

                if (!(row == VGA_V_VISIBLE - 1 && col == VGA_H_TOTAL - 1))
                    @(posedge vif_vga.vga_clk);
            end
        end
    endtask

    task compare_frame(input byte unsigned frame_pixels[76800], input string tag);
        int mismatch_cnt = 0;

        for (int i = 0; i < 76800; i++) begin
            if (frame_pixels[i] !== test_image[i]) begin
                mismatch_cnt++;
                if (mismatch_cnt <= 5)
                    `uvm_error("VGA_FRAME", $sformatf("%s mismatch at pixel %0d: got=0x%02x exp=0x%02x", tag, i, frame_pixels[i], test_image[i]))
            end
        end

        if (mismatch_cnt == 0)
            `uvm_info("TEST", $sformatf("%s frame compare PASS (76800 pixels)", tag), UVM_LOW)
        else
            `uvm_error("VGA_FRAME", $sformatf("%s frame compare FAIL: %0d mismatches", tag, mismatch_cnt))
    endtask
endclass : vga_base_test

// -----------------------------------------------------------------------------
// Timing Test: VGA 时序参数验证
// -----------------------------------------------------------------------------
class vga_timing_test extends vga_base_test;
    `uvm_component_utils(vga_timing_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        time hsync_t0;
        time hsync_t1;
        time hsync_t2;
        time vsync_t0;
        time vsync_t1;
        time vsync_t2;
        time exp_hsync_low  = 3840ns;
        time exp_line       = 32000ns;
        time exp_vsync_low  = 64000ns;
        time exp_frame      = 16800000ns;

        wait_until_ready();

        @(negedge vif_vga.vga_hs);
        hsync_t0 = $time;
        @(posedge vif_vga.vga_hs);
        hsync_t1 = $time;
        @(negedge vif_vga.vga_hs);
        hsync_t2 = $time;

        if (hsync_t1 - hsync_t0 != exp_hsync_low)
            `uvm_error("VGA_TIMING", $sformatf("hsync low width mismatch: got %0t exp %0t", hsync_t1 - hsync_t0, exp_hsync_low))

        if (hsync_t2 - hsync_t0 != exp_line)
            `uvm_error("VGA_TIMING", $sformatf("line period mismatch: got %0t exp %0t", hsync_t2 - hsync_t0, exp_line))

        @(negedge vif_vga.vga_vs);
        vsync_t0 = $time;
        @(posedge vif_vga.vga_vs);
        vsync_t1 = $time;
        @(negedge vif_vga.vga_vs);
        vsync_t2 = $time;

        if (vsync_t1 - vsync_t0 != exp_vsync_low)
            `uvm_error("VGA_TIMING", $sformatf("vsync low width mismatch: got %0t exp %0t", vsync_t1 - vsync_t0, exp_vsync_low))

        if (vsync_t2 - vsync_t0 != exp_frame)
            `uvm_error("VGA_TIMING", $sformatf("frame period mismatch: got %0t exp %0t", vsync_t2 - vsync_t0, exp_frame))

        wait_visible_frame_start();
        if (!vif_vga.vga_blank_n)
            `uvm_error("VGA_TIMING", "blank_n should be 1 at top-left visible pixel")
        if (vif_vga.vga_sync_n !== 1'b0)
            `uvm_error("VGA_TIMING", $sformatf("sync_n should stay 0, got %0b", vif_vga.vga_sync_n))

        @(negedge vif_vga.vga_hs);
        if (vif_vga.vga_blank_n !== 1'b0)
            `uvm_error("VGA_TIMING", "blank_n should be 0 during hsync interval")

        `uvm_info("TEST", "vga_timing_test: timing checks passed", UVM_NONE)
    endtask
endclass : vga_timing_test

// -----------------------------------------------------------------------------
// Pixel Test: RGB332→RGB888 映射验证
// -----------------------------------------------------------------------------
class vga_pixel_test extends vga_base_test;
    `uvm_component_utils(vga_pixel_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        byte unsigned got_r;
        byte unsigned got_g;
        byte unsigned got_b;
        byte unsigned exp_r;
        byte unsigned exp_g;
        byte unsigned exp_b;
        byte unsigned exp_px;
        int img_idx;
        int sample_idx = 0;
        int sample_x[$] = '{0, 1, 2, 17, 126, 319, 320, 511, 638, 639};
        int sample_y[$] = '{0, 0, 1, 2, 33, 120, 121, 238, 478, 479};

        wait_visible_frame_start();

        for (int row = 0; row < VGA_V_VISIBLE; row++) begin
            for (int col = 0; col < VGA_H_TOTAL; col++) begin
                if (col < VGA_H_VISIBLE && sample_idx < sample_x.size() &&
                    row == sample_y[sample_idx] && col == sample_x[sample_idx]) begin
                    got_r = vif_vga.vga_r;
                    got_g = vif_vga.vga_g;
                    got_b = vif_vga.vga_b;

                    img_idx = (row >> 1) * 320 + (col >> 1);
                    exp_px  = test_image[img_idx];
                    ref_rgb332_to_888(exp_px, exp_r, exp_g, exp_b);

                    if (!vif_vga.vga_blank_n)
                        `uvm_error("VGA_PIXEL", $sformatf("blank_n low at visible sample (%0d,%0d)", col, row))

                    if (got_r !== exp_r || got_g !== exp_g || got_b !== exp_b) begin
                        `uvm_error("VGA_PIXEL", $sformatf(
                            "pixel mismatch at (%0d,%0d): got=(%02x,%02x,%02x) exp=(%02x,%02x,%02x) src=0x%02x",
                            col, row, got_r, got_g, got_b, exp_r, exp_g, exp_b, exp_px))
                    end

                    sample_idx++;
                end

                if (!(row == VGA_V_VISIBLE - 1 && col == VGA_H_TOTAL - 1))
                    @(posedge vif_vga.vga_clk);
            end
        end

        if (sample_idx != sample_x.size())
            `uvm_error("VGA_PIXEL", $sformatf("sample collection incomplete: checked %0d/%0d points", sample_idx, sample_x.size()))

        `uvm_info("TEST", "vga_pixel_test: sampled RGB332→RGB888 mapping passed", UVM_NONE)
    endtask
endclass : vga_pixel_test

// -----------------------------------------------------------------------------
// Full Frame Test: 连续验证 ≥2 帧
// -----------------------------------------------------------------------------
class vga_fullframe_test extends vga_base_test;
    `uvm_component_utils(vga_fullframe_test)

    int unsigned required_frames = 2;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        byte unsigned frame_pixels[76800];

        for (int frame_idx = 0; frame_idx < required_frames; frame_idx++) begin
            capture_frame(frame_pixels);
            compare_frame(frame_pixels, $sformatf("frame%0d", frame_idx + 1));
        end

        `uvm_info("TEST", $sformatf("vga_fullframe_test: %0d full frame(s) verified", required_frames), UVM_NONE)
    endtask
endclass : vga_fullframe_test

`endif // VGA_TESTS_SV
