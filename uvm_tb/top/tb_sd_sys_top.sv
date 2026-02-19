// =============================================================================
// tb_sd_sys_top.sv
// Layer 3 — 全系统端到端仿真顶层
//
// 实例化:
//   ① top_sd_vga (完整 DUT)
//   ② sd_card_model (预加载合法 FAT32 镜像)
//   ③ sd_sys_if (VGA 输出 + RAM 写接口观测)
//   ④ run_test()
// =============================================================================
`timescale 1ns/1ps
`include "uvm_macros.svh"

module tb_sd_sys_top;
    import uvm_pkg::*;
    import sd_sys_pkg::*;

    // =========================================================================
    // 时钟和复位
    // =========================================================================
    logic CLOCK_50;
    logic rst_n;     // active-low, 对应 KEY[0]

    initial CLOCK_50 = 0;
    always #10 CLOCK_50 = ~CLOCK_50;  // 50 MHz

    initial begin
        rst_n = 0;
        repeat (20) @(posedge CLOCK_50);
        rst_n = 1;
    end

    logic [3:0] KEY;
    assign KEY[0] = rst_n;
    assign KEY[3:1] = 3'b111;

    // =========================================================================
    // SD 总线
    // =========================================================================
    logic        SD_CLK;
    wire         SD_CMD;
    wire  [3:0]  SD_DAT;
    logic        SD_CD;

    // 卡模型驱动
    logic        card_cmd_oe;
    logic        card_cmd_out;
    logic [3:0]  card_dat_oe;
    logic [3:0]  card_dat_out;

    // CMD 三态
    logic        dut_sdcmdoe;
    tri1         SD_CMD_bus;
    assign SD_CMD_bus = dut_sdcmdoe   ? SD_CMD  : 1'bz;
    assign SD_CMD_bus = card_cmd_oe   ? card_cmd_out : 1'bz;

    // DAT 三态
    tri1 [3:0]   SD_DAT_bus;
    genvar gi;
    generate
        for (gi = 0; gi < 4; gi++) begin : dat_drv
            assign SD_DAT_bus[gi] = card_dat_oe[gi] ? card_dat_out[gi] : 1'bz;
        end
    endgenerate

    // =========================================================================
    // VGA 输出信号
    // =========================================================================
    logic        VGA_CLK;
    logic        VGA_HS;
    logic        VGA_VS;
    logic        VGA_BLANK_N;
    logic        VGA_SYNC_N;
    logic [7:0]  VGA_R;
    logic [7:0]  VGA_G;
    logic [7:0]  VGA_B;

    // 调试输出 (不用于验证)
    logic [9:0]  LEDR;
    logic [6:0]  HEX0;

    // =========================================================================
    // 接口
    // =========================================================================
    sd_sys_if u_sys_if (.clk_50(CLOCK_50), .rst_n(rst_n));

    // 连接 VGA 观测
    assign u_sys_if.vga_clk     = VGA_CLK;
    assign u_sys_if.vga_hs      = VGA_HS;
    assign u_sys_if.vga_vs      = VGA_VS;
    assign u_sys_if.vga_blank_n = VGA_BLANK_N;
    assign u_sys_if.vga_sync_n  = VGA_SYNC_N;
    assign u_sys_if.vga_r       = VGA_R;
    assign u_sys_if.vga_g       = VGA_G;
    assign u_sys_if.vga_b       = VGA_B;
    // 连接 RAM 写接口和状态标志
    // (通过层次引用从 DUT 内部 sd_file_reader 取出)
    assign u_sys_if.ram_waddr   = u_dut.u_file_reader.ram_addr;
    assign u_sys_if.ram_wdata   = u_dut.u_file_reader.ram_wdata;
    assign u_sys_if.ram_we      = u_dut.u_file_reader.ram_we;
    assign u_sys_if.file_found  = u_dut.file_found;
    assign u_sys_if.read_done   = u_dut.read_done;

    // =========================================================================
    // DUT: top_sd_vga
    // =========================================================================
    top_sd_vga u_dut (
        .CLOCK_50   (CLOCK_50),
        .KEY        (KEY),
        .SD_CLK     (SD_CLK),
        .SD_CMD     (SD_CMD_bus),
        .SD_DAT     (SD_DAT_bus),
        .SD_CD      (SD_CD),
        .VGA_CLK    (VGA_CLK),
        .VGA_HS     (VGA_HS),
        .VGA_VS     (VGA_VS),
        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N (VGA_SYNC_N),
        .VGA_R      (VGA_R),
        .VGA_G      (VGA_G),
        .VGA_B      (VGA_B),
        .LEDR       (LEDR),
        .HEX0       (HEX0)
    );

    // =========================================================================
    // SD 卡行为模型 + 镜像预加载
    // =========================================================================
    sd_card_model #(
        .TOTAL_SECTORS (8192),
        .NCR_CYCLES    (8),
        .RCA_VAL       (32'h0001_0000)
    ) u_card_model (
        .sdclk        (SD_CLK),
        .sdcmd_obs    (SD_CMD_bus),
        .card_cmd_oe  (card_cmd_oe),
        .card_cmd_out (card_cmd_out),
        .card_dat_oe  (card_dat_oe),
        .card_dat_out (card_dat_out)
    );

    // 预加载 FAT32 镜像 (由 fat32_image_gen 生成)
    initial begin
        // TODO: fat32_image_gen::generate_image(u_card_model.mem, 8192, 1)
        // 待 fat32_image_gen 集成后替换此行
        $display("[SYS_TB] SD card model initialized, waiting for DUT to start...");
    end

    // =========================================================================
    // UVM 配置与启动
    // =========================================================================
    initial begin
        uvm_config_db #(virtual sd_sys_if.vga_mon)::set(null,  "uvm_test_top.*", "vif_vga",   u_sys_if.vga_mon);
        uvm_config_db #(virtual sd_sys_if.fat32_mon)::set(null, "uvm_test_top.*", "vif_fat32", u_sys_if.fat32_mon);
        run_test();
    end

    // =========================================================================
    // 超时看门狗 (系统级仿真时间较长)
    // =========================================================================
    initial begin
        #200_000_000;  // 200ms
        `uvm_fatal("TIMEOUT", "sys tb timeout: 200ms exceeded")
    end

    initial begin
        $dumpfile("sd_sys_wave.vcd");
        $dumpvars(0, tb_sd_sys_top);
    end

endmodule : tb_sd_sys_top
