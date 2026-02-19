// =============================================================================
// sdcmd_if.sv
// sdcmd_ctrl 接口定义
// 建模三态 sdcmd 总线：DUT 侧驱动 (sdcmdoe + dut_cmd_out) 与
//                        卡模型侧驱动 (card_oe + card_cmd_out) 共同仲裁
// =============================================================================
`ifndef SDCMD_IF_SV
`define SDCMD_IF_SV

interface sdcmd_if (
    input logic clk,    // 系统时钟 (50 MHz)
    input logic rstn    // active-low 复位
);

    // -------------------------------------------------------------------------
    // DUT 输入侧控制信号 (由 Driver 驱动)
    // -------------------------------------------------------------------------
    logic [15:0] clkdiv;    // sdclk 分频系数
    logic [15:0] precnt;    // 响应前等待周期 (Ncr)
    logic [5:0]  cmd;       // 命令索引
    logic [31:0] arg;       // 命令参数
    logic        start;     // 命令发送触发 (脉冲)

    // -------------------------------------------------------------------------
    // DUT 输出侧状态信号 (由 Monitor 采样)
    // -------------------------------------------------------------------------
    logic        busy;      // 控制器忙
    logic        done;      // 命令完成
    logic        timeout;   // 响应超时
    logic        syntaxe;   // 响应校验错误 (cmd index 不匹配)
    logic [31:0] resparg;   // 响应参数 resp[39:8]

    // -------------------------------------------------------------------------
    // SD CMD 三态总线建模
    // -------------------------------------------------------------------------
    logic        sdclk;         // SD 时钟 (由 DUT 驱动)
    logic        sdcmdoe;       // DUT CMD 输出使能
    logic        dut_cmd_out;   // DUT CMD 输出值
    logic        card_oe;       // 卡模型 CMD 输出使能
    logic        card_cmd_out;  // 卡模型 CMD 输出值

    // 三态仲裁: DUT 或 Card 驱动，均无效时线上为高 (pullup)
    // 实际在 top_tb 中用 tri + pullup 实例化 sdcmd 信号
    // wire sdcmd = sdcmdoe    ? dut_cmd_out  :
    //              card_oe     ? card_cmd_out :
    //              1'bz;  // 配合 pullup -> 1
    logic sdcmd_wire; // 供 Monitor 采样的 sdcmd 观测信号

    // -------------------------------------------------------------------------
    // Modports
    // -------------------------------------------------------------------------

    // host driver 使用: 写控制信号，读状态
    modport host_drv (
        input  clk, rstn,
        output clkdiv, precnt, cmd, arg, start,
        input  busy, done, timeout, syntaxe, resparg,
        input  sdclk, sdcmd_wire
    );

    // host monitor 使用: 只读所有信号
    modport host_mon (
        input  clk, rstn,
        input  clkdiv, precnt, cmd, arg, start,
        input  busy, done, timeout, syntaxe, resparg,
        input  sdclk, sdcmdoe, dut_cmd_out,
        input  card_oe, card_cmd_out,
        input  sdcmd_wire
    );

    // 卡模型 responder 使用: 驱动卡侧，观测 sdclk 和 cmd 线
    modport card_resp (
        input  sdclk,
        input  sdcmd_wire,
        output card_oe, card_cmd_out
    );

    // -------------------------------------------------------------------------
    // 辅助任务: 等待 sdclk 上升沿
    // -------------------------------------------------------------------------
    task automatic wait_sdclk_posedge();
        @(posedge sdclk);
    endtask

    // 等待 sdclk 下降沿
    task automatic wait_sdclk_negedge();
        @(negedge sdclk);
    endtask

endinterface : sdcmd_if

`endif // SDCMD_IF_SV
