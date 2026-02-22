// =============================================================================
// tb_sd_reader_top.sv
// Layer 2 — sd_reader 子系统仿真顶层
//
// 实例化:
//   ① sd_reader  (DUT, SIMULATE=1 加速仿真)
//   ② sd_card_model (含预加载 FAT32 镜像)
//   ③ sd_reader_if
//   ④ run_test()
// =============================================================================
`timescale 1ns/1ps
`include "uvm_macros.svh"

module tb_sd_reader_top;
    import uvm_pkg::*;
    import sd_reader_pkg::*;
    import fat32_image_gen::*;

    // 动态数组，用于 FAT32 镜像生成和 scoreboard 引用
    logic [7:0] card_mem_dyn[];

    // =========================================================================
    // 时钟和复位
    // =========================================================================
    logic clk;
    logic rst_n;

    initial clk = 0;
    always #10 clk = ~clk;  // 50 MHz

    initial begin
        rst_n = 0;
        repeat (20) @(posedge clk);
        rst_n = 1;
    end

    // =========================================================================
    // sdcmd / sddat 三态总线
    // =========================================================================
    logic       card_cmd_oe;
    logic       card_cmd_out;

    tri1  sdcmd_bus;
    assign sdcmd_bus = (card_cmd_oe) ? u_if.card_cmd_out : 1'bz;

    logic [3:0] card_dat_oe;
    logic [3:0] card_dat_out;
    tri1  [3:0] sddat_bus;
    genvar gi;
    generate
        for (gi = 0; gi < 4; gi++) begin : dat_drv
            assign sddat_bus[gi] = card_dat_oe[gi] ? card_dat_out[gi] : 1'bz;
        end
    endgenerate

    // =========================================================================
    // 接口
    // =========================================================================
    sd_reader_if u_if (.clk(clk), .rst_n(rst_n));

    // 连接接口观测信号
    assign u_if.sdcmd_obs    = sdcmd_bus;
    assign u_if.sddat_obs    = sddat_bus;
    assign u_if.card_cmd_oe  = card_cmd_oe;
    assign u_if.card_cmd_out = card_cmd_out;
    assign u_if.card_dat_oe  = card_dat_oe;
    assign u_if.card_dat_out = card_dat_out;

    // =========================================================================
    // DUT: sd_reader (SIMULATE=1 缩短初始化等待)
    // =========================================================================
    wire sdclk_dut;

    sd_reader #(
        .CLK_DIV  (3'd2),
        .SIMULATE (1)
    ) u_sd_reader (
        .clk      (clk),
        .rst_n    (rst_n),
        .rstart   (u_if.rstart),
        .rsector  (u_if.rsector),
        .rdone    (u_if.rdone),
        .rbusy    (u_if.rbusy),
        .outen    (u_if.outen),
        .outbyte  (u_if.outbyte),
        .sdclk    (sdclk_dut),
        .sddata0  (sddat_bus[0]),
        .sdcmd    (sdcmd_bus)
    );

    assign u_if.sdclk = sdclk_dut;

    // =========================================================================
    // SD 卡行为模型 + FAT32 镜像生成
    // =========================================================================
    sd_card_model #(
        .TOTAL_SECTORS (4096),
        .NCR_CYCLES    (80),
        .RCA_VAL       (32'h0001_0000)
    ) u_card_model (
        .sdclk        (sdclk_dut),
        .ncr_cycles_dyn(16'd0),
        .sdcmd_obs    (sdcmd_bus),
        .card_cmd_oe  (card_cmd_oe),
        .card_cmd_out (card_cmd_out),
        .card_dat_oe  (card_dat_oe),
        .card_dat_out (card_dat_out)
    );

    // 预加载 FAT32 镜像到 sd_card_model.mem
    initial begin
        // sd_card_model.mem 是固定大小数组，generate_image 需要动态数组 ref
        // 因此先用模块级动态数组生成镜像，再复制回固定数组
        automatic int mem_size = 4096 * 512;
        card_mem_dyn = new[mem_size];
        foreach (card_mem_dyn[i]) card_mem_dyn[i] = 8'h00;
        fat32_image_gen::generate_image(card_mem_dyn, 4096);
        card_mem_dyn[510] = 8'h55;
        card_mem_dyn[511] = 8'hAA;
        // 复制到固定大小的 sd_card_model.mem
        for (int i = 0; i < mem_size; i++)
            u_card_model.mem[i] = card_mem_dyn[i];
    end

    // =========================================================================
    // UVM 配置与启动
    // =========================================================================
    initial begin
        uvm_config_db #(virtual sd_reader_if.host_drv)::set(null, "uvm_test_top.*", "vif", u_if.host_drv);
        uvm_config_db #(virtual sd_reader_if.host_mon)::set(null, "uvm_test_top.*", "vif", u_if.host_mon);
        // 传递 card_mem 动态数组引用给 scoreboard
        uvm_config_db #(mem_byte_da_t)::set(null, "uvm_test_top.*", "card_mem", card_mem_dyn);

        run_test();
    end

    // =========================================================================
    // 超时看门狗
    // =========================================================================
    initial begin
        #50_000_000;  // 50ms (SIMULATE=1 初始化约几百us)
        `uvm_fatal("TIMEOUT", "sd_reader tb timeout: 50ms exceeded")
    end

    initial begin
        $dumpfile("sd_reader_wave.vcd");
        $dumpvars(0, tb_sd_reader_top);
    end

endmodule : tb_sd_reader_top
