// =============================================================================
// tb_sdcmd_ctrl_top.sv
// Layer 1 顶层 — sdcmd_ctrl 模块级 UVM 仿真顶层
//
// 实例化:
//   ① sdcmd_if          — DUT 接口 (含三态 sdcmd 建模)
//   ② sdcmd_ctrl (DUT)  — 被测模块
//   ③ sd_card_model     — SD 卡行为模型 (自动响应)
//   时钟/复位生成
//   run_test() 启动 UVM
// =============================================================================
`timescale 1ns/1ps
`ifndef TB_SDCMD_CTRL_TOP_SV
`define TB_SDCMD_CTRL_TOP_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import sdcmd_ctrl_pkg::*;

module tb_sdcmd_ctrl_top;

    // =========================================================================
    // 时钟 & 复位
    // =========================================================================
    logic clk  = 0;
    logic rstn = 0;

    always #10 clk = ~clk;  // 50 MHz (周期 20ns)

    initial begin
        rstn = 0;
        repeat (20) @(posedge clk);
        rstn = 1;
    end

    // =========================================================================
    // 接口实例化
    // =========================================================================
    sdcmd_if u_sdcmd_if (.clk(clk), .rstn(rstn));

    // =========================================================================
    // 三态 sdcmd 总线
    // =========================================================================
    // DUT 通过 inout sdcmd 端口直接驱动总线
    // 卡模型驱动: card_oe=1 时，sdcmd = card_cmd_out
    // 均无效时: 通过 pullup 保持高 (tri1)
    tri1 sdcmd_bus;

    // 只保留卡模型的驱动，DUT 通过 inout 端口直接驱动总线
    assign sdcmd_bus = u_sdcmd_if.card_oe ? u_sdcmd_if.card_cmd_out : 1'bz;
    assign u_sdcmd_if.sdcmd_wire = sdcmd_bus;

    // DAT 线 (在 Layer 1 仅观测，不传数据)
    tri1 sddat_bus;

    // =========================================================================
    // DUT: sdcmd_ctrl
    // =========================================================================
    sdcmd_ctrl u_dut (
        .rstn     (rstn),
        .clk      (clk),
        .sdclk    (u_sdcmd_if.sdclk),
        .sdcmd    (sdcmd_bus),
        .clkdiv   (u_sdcmd_if.clkdiv),
        .start    (u_sdcmd_if.start),
        .precnt   (u_sdcmd_if.precnt),
        .cmd      (u_sdcmd_if.cmd),
        .arg      (u_sdcmd_if.arg),
        .busy     (u_sdcmd_if.busy),
        .done     (u_sdcmd_if.done),
        .timeout  (u_sdcmd_if.timeout),
        .syntaxe  (u_sdcmd_if.syntaxe),
        .resparg  (u_sdcmd_if.resparg),
        .sdcmdoe  (u_sdcmd_if.sdcmdoe)
        // 注意: dut_cmd_out 实际上是 DUT 内部的 sdcmd 输出驱动值
        // 若 DUT 使用 inout 端口，需通过 sdcmdoe 和总线观测分离
    );

    // =========================================================================
    // SD 卡行为模型
    // =========================================================================
    sd_card_model #(
        .TOTAL_SECTORS (4096),
        .NCR_CYCLES    (8),
        .RCA_VAL       (32'h0001_0000)
    ) u_card_model (
        .sdclk        (u_sdcmd_if.sdclk),
        .sdcmd_obs    (sdcmd_bus),
        .card_cmd_oe  (u_sdcmd_if.card_oe),
        .card_cmd_out (u_sdcmd_if.card_cmd_out),
        .card_dat_oe  (/* not used in L1 */),
        .card_dat_out (/* not used in L1 */)
    );

    // =========================================================================
    // UVM 启动
    // =========================================================================
    initial begin
        // 将接口传给 UVM config_db
        uvm_config_db #(virtual sdcmd_if.host_drv)::set(null, "uvm_test_top.*", "vif", u_sdcmd_if);
        uvm_config_db #(virtual sdcmd_if.host_mon)::set(null, "uvm_test_top.*", "vif", u_sdcmd_if);

        // 运行指定的 test (通过 +UVM_TESTNAME=xxx 命令行参数指定)
        run_test("sdcmd_smoke_test");
    end

    // =========================================================================
    // 仿真超时保护
    // =========================================================================
    initial begin
        #10_000_000;  // 10ms 超时
        `uvm_fatal("TIMEOUT", "Simulation timeout!")
    end

    // =========================================================================
    // 波形转储
    // =========================================================================
    initial begin
        $dumpfile("tb_sdcmd_ctrl_top.vcd");
        $dumpvars(0, tb_sdcmd_ctrl_top);
    end

endmodule : tb_sdcmd_ctrl_top

`endif // TB_SDCMD_CTRL_TOP_SV
