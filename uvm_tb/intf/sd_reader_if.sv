// =============================================================================
// sd_reader_if.sv
// sd_reader 子系统接口定义
// 覆盖 Host 侧（rstart/rsector/rbusy/rdone/outen/outbyte）
//      SD 总线侧（sdclk / sdcmd(tri) / sddat[3:0](tri)）
// =============================================================================
`ifndef SD_READER_IF_SV
`define SD_READER_IF_SV

interface sd_reader_if (
    input logic clk,
    input logic rst_n
);

    // -------------------------------------------------------------------------
    // Host 控制接口 (sd_file_reader → sd_reader)
    // -------------------------------------------------------------------------
    logic        rstart;         // 读扇区请求 (脉冲)
    logic [31:0] rsector;        // 目标扇区地址

    // -------------------------------------------------------------------------
    // Host 状态接口 (sd_reader → sd_file_reader)
    // -------------------------------------------------------------------------
    logic        rbusy;          // SD 读取器忙 (初始化中 / 传输中)
    logic        rdone;          // 单次扇区读取完成
    logic        outen;          // 输出字节有效
    logic [7:0]  outbyte;        // 输出字节数据

    // -------------------------------------------------------------------------
    // SD 总线侧信号 (sd_reader ↔ SD 卡模型)
    // -------------------------------------------------------------------------
    logic        sdclk;          // SD 时钟 (由 sd_reader 内 sdcmd_ctrl 生成)
    logic        sdcmd_oe;       // DUT CMD 输出使能
    logic        sdcmd_out;      // DUT CMD 输出值
    logic        card_cmd_oe;    // 卡模型 CMD 输出使能
    logic        card_cmd_out;   // 卡模型 CMD 输出值
    logic        sdcmd_obs;      // CMD 线观测值 (三态仲裁结果)

    // DAT 线 (1-bit 模式，仅 DAT[0] 有效)
    logic [3:0]  sddat_oe;       // DUT DAT 输出使能 (实际仅 [0])
    logic [3:0]  sddat_out;      // DUT DAT 输出值
    logic [3:0]  card_dat_oe;    // 卡模型 DAT 输出使能
    logic [3:0]  card_dat_out;   // 卡模型 DAT 输出值
    logic [3:0]  sddat_obs;      // DAT 线观测值

    // -------------------------------------------------------------------------
    // Modports
    // -------------------------------------------------------------------------

    // host driver: 驱动 rstart/rsector，监测 rbusy/rdone/outen/outbyte
    modport host_drv (
        input  clk, rst_n,
        output rstart, rsector,
        input  rbusy, rdone, outen, outbyte
    );

    // host monitor: 观测所有 host 侧信号
    modport host_mon (
        input  clk, rst_n,
        input  rstart, rsector,
        input  rbusy, rdone, outen, outbyte
    );

    // 卡模型 responder: 驱动 DAT/CMD 卡侧，观测 sdclk
    modport card_resp (
        input  sdclk,
        input  sdcmd_obs,
        output card_cmd_oe, card_cmd_out,
        output card_dat_oe, card_dat_out,
        input  sddat_obs
    );

endinterface : sd_reader_if

`endif // SD_READER_IF_SV
