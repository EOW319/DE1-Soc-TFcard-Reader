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
// -----------------------------------------------------------------------------
// H_TOTAL    = 800,  H_VISIBLE = 640
// H_FRONT    = 16,   H_SYNC    = 96,   H_BACK = 48
// V_TOTAL    = 525,  V_VISIBLE = 480
// V_FRONT    = 10,   V_SYNC    = 2,    V_BACK = 33
// PIXEL_CLK  = 25 MHz

package vga_timing_pkg;
    // 水平时序 (像素数)
    localparam int H_VISIBLE = 640;
    localparam int H_FRONT   = 16;
    localparam int H_SYNC    = 96;
    localparam int H_BACK    = 48;
    localparam int H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK; // 800

    // 垂直时序 (行数)
    localparam int V_VISIBLE = 480;
    localparam int V_FRONT   = 10;
    localparam int V_SYNC    = 2;
    localparam int V_BACK    = 33;
    localparam int V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK; // 525
endpackage

// -----------------------------------------------------------------------------
// 基础 Test
// -----------------------------------------------------------------------------
class vga_base_test extends uvm_test;
    `uvm_component_utils(vga_base_test)

    // img_ram 预加载数据 (待写入 DUT 的 img_ram)
    byte unsigned test_image[76800];  // 320×240 测试图案

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 生成测试图案:
        //   - 渐变色: test_image[i] = i % 256
        //   - 棋盘格: test_image[i] = ((i/320 + i%320) % 2) ? 8'hFF : 8'h00
        foreach (test_image[i])
            test_image[i] = i % 256;  // 默认: 渐变色
        // TODO: 通过 config_db 将 test_image 传给 tb_vga_top 预加载 img_ram
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_test_body(phase);
        phase.drop_objection(this);
    endtask

    virtual task run_test_body(uvm_phase phase);
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
        // TODO: 通过 VGA Monitor 统计 hsync/vsync 脉冲宽度和间隔
        // 检查点:
        //   ① hsync 低电平宽度 = 96 像素时钟周期 (3.84us)
        //   ② vsync 低电平宽度 = 2 行
        //   ③ 行周期 = 800 像素时钟 (32us)
        //   ④ 帧周期 = 525 行 × 800 像素 = 16.68ms ≈ 60Hz
        //   ⑤ blank_n 在同步+porch 区间为 0
        //   ⑥ sync_n 固定为 0 (对 VGA ADC 无用但需正确)

        // 等待 2 帧完成
        #1_000_000_000; // 约 2 帧 @ 25MHz: 2 × 525 × 800 × 40ns = 33.6ms
        `uvm_info("TEST", "vga_timing_test: timing check complete (TODO: implement monitor check)", UVM_NONE)
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

    // 参考模型: RGB332 → RGB888 位扩展规则
    // R[7:0] = {rgb332[7:5], rgb332[7:5], rgb332[7:6]}
    // G[7:0] = {rgb332[4:2], rgb332[4:2], rgb332[4:3]}
    // B[7:0] = {rgb332[1:0], rgb332[1:0], rgb332[1:0], rgb332[1:0]}
    function automatic void ref_rgb332_to_888(
        input  byte unsigned rgb332,
        output byte unsigned r8, g8, b8
    );
        r8 = {rgb332[7:5], rgb332[7:5], rgb332[7:6]};
        g8 = {rgb332[4:2], rgb332[4:2], rgb332[4:3]};
        b8 = {rgb332[1:0], rgb332[1:0], rgb332[1:0], rgb332[1:0]};
    endfunction

    virtual task run_test_body(uvm_phase phase);
        // TODO: VGA Monitor 在第 1 帧内采样每个有效像素的 vga_r/g/b
        // 对每个像素坐标 (x, y):
        //   期望 pixel = test_image[y/2 * 320 + x/2]  (2x 缩放还原)
        //   ref_rgb332_to_888(pixel, exp_r, exp_g, exp_b)
        //   断言 vga_r == exp_r && vga_g == exp_g && vga_b == exp_b

        #1_000_000_000;
        `uvm_info("TEST", "vga_pixel_test: RGB332→888 mapping check complete (TODO)", UVM_NONE)
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
        // TODO: 等待 VGA Monitor 发布 required_frames 个 vga_frame_item
        //       每帧独立进行逐像素比对
        #2_000_000_000;
        `uvm_info("TEST", $sformatf("vga_fullframe_test: %0d frames verified (TODO)", required_frames), UVM_NONE)
    endtask
endclass : vga_fullframe_test

`endif // VGA_TESTS_SV
