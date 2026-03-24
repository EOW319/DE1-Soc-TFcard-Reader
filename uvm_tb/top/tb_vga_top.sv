// =============================================================================
// tb_vga_top.sv
// VGA 控制器独立验证顶层
//
// 实例化:
//   ① vga_ctrl (DUT)
//   ② img_ram  (预加载已知图案)
//   ③ run_test()  (启动 VGA 相关 tests)
// =============================================================================
`timescale 1ns/1ps
`include "uvm_macros.svh"

module tb_vga_top;
    import uvm_pkg::*;
    import sd_sys_pkg::*;  // vga_tests 在 sd_sys_pkg 中定义

    // =========================================================================
    // 时钟和复位
    // =========================================================================
    logic clk_25;  // 25 MHz 像素时钟
    logic rst_n;

    initial clk_25 = 0;
    always #20 clk_25 = ~clk_25;  // 25 MHz (周期 40ns)

    initial begin
        rst_n = 0;
        repeat (10) @(posedge clk_25);
        rst_n = 1;
    end

    // =========================================================================
    // img_ram 预加载图案
    // =========================================================================
    // img_ram 的写端口 (由 initial 块驱动，模拟 sd_file_reader 写入完成后的状态)
    logic [16:0] waddr;
    logic [7:0]  wdata;
    logic        we;

    // =========================================================================
    // VGA 输出信号
    // =========================================================================
    logic [16:0] ram_raddr;
    logic [7:0]  ram_rdata;
    logic        vga_clk;
    logic        vga_hs;
    logic        vga_vs;
    logic        vga_blank_n;
    logic        vga_sync_n;
    logic [7:0]  vga_r;
    logic [7:0]  vga_g;
    logic [7:0]  vga_b;
    logic        preload_done;

    // =========================================================================
    // 子模块: img_ram + vga_ctrl
    // =========================================================================
    img_ram u_img_ram (
        .clk    (clk_25),
        .we     (we),
        .waddr  (waddr),
        .wdata  (wdata),
        .raddr  (ram_raddr),
        .rdata  (ram_rdata)
    );

    vga_ctrl u_vga_ctrl (
        .clk       (clk_25),
        .rst_n     (rst_n),
        .img_data  (ram_rdata),
        .ram_addr  (ram_raddr),
        .vga_clk   (vga_clk),
        .vga_hsync (vga_hs),
        .vga_vsync (vga_vs),
        .vga_blank_n (vga_blank_n),
        .vga_sync_n  (vga_sync_n),
        .vga_r     (vga_r),
        .vga_g     (vga_g),
        .vga_b     (vga_b)
    );

    // =========================================================================
    // 预加载渐变色图案到 img_ram
    // =========================================================================
    integer i;
    initial begin
        we    = 0;
        waddr = 0;
        wdata = 0;
        preload_done = 0;
        @(posedge rst_n);
        @(posedge clk_25);

        // 写入渐变色: pixel[i] = i % 256
        for (i = 0; i < 76800; i++) begin
            we    <= 1;
            waddr <= i[16:0];
            wdata <= i[7:0];
            @(posedge clk_25);
        end
        we <= 0;
        preload_done <= 1;
        $display("[VGA_TB] img_ram preload done (76800 bytes)");
    end

    // =========================================================================
    // 系统级接口 (复用 sd_sys_if 的 VGA modport)
    // =========================================================================
    sd_sys_if u_sys_if (.clk_50(clk_25), .rst_n(rst_n));
    assign u_sys_if.vga_clk     = vga_clk;
    assign u_sys_if.vga_hs      = vga_hs;
    assign u_sys_if.vga_vs      = vga_vs;
    assign u_sys_if.vga_blank_n = vga_blank_n;
    assign u_sys_if.vga_sync_n  = vga_sync_n;
    assign u_sys_if.vga_r       = vga_r;
    assign u_sys_if.vga_g       = vga_g;
    assign u_sys_if.vga_b       = vga_b;
    assign u_sys_if.preload_done = preload_done;

    // =========================================================================
    // UVM 配置与启动
    // =========================================================================
    initial begin
        uvm_config_db #(virtual sd_sys_if.vga_mon)::set(null, "uvm_test_top",   "vif_vga", u_sys_if.vga_mon);
        uvm_config_db #(virtual sd_sys_if.vga_mon)::set(null, "uvm_test_top.*", "vif_vga", u_sys_if.vga_mon);
        run_test();
    end

    // =========================================================================
    // 超时看门狗: 2 帧 @ 25MHz = 2 × 525 × 800 × 40ns ≈ 33.6ms
    // =========================================================================
    initial begin
        #100_000_000;  // 100ms 超时
        `uvm_fatal("TIMEOUT", "VGA tb timeout: 100ms exceeded")
    end

    initial begin
        $dumpfile("vga_wave.vcd");
        $dumpvars(0, tb_vga_top);
    end

endmodule : tb_vga_top
