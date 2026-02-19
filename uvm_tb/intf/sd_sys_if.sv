// =============================================================================
// sd_sys_if.sv
// 系统级 (top_sd_vga) 接口定义
// 主要用于 VGA Monitor 采样 VGA 输出信号，以及
// sd_file_reader 的 RAM 写接口观测
// =============================================================================
`ifndef SD_SYS_IF_SV
`define SD_SYS_IF_SV

interface sd_sys_if (
    input logic clk_50,   // 板载 50MHz 时钟
    input logic rst_n     // active-low 复位 (对应 KEY[0])
);

    // -------------------------------------------------------------------------
    // VGA 输出信号 (由 DUT top_sd_vga 驱动，VGA Monitor 被动采样)
    // -------------------------------------------------------------------------
    logic        vga_clk;
    logic        vga_hs;
    logic        vga_vs;
    logic        vga_blank_n;
    logic        vga_sync_n;
    logic [7:0]  vga_r;
    logic [7:0]  vga_g;
    logic [7:0]  vga_b;

    // -------------------------------------------------------------------------
    // img_ram 写接口观测 (sd_file_reader → img_ram，FAT32 Scoreboard 用)
    // -------------------------------------------------------------------------
    logic [16:0] ram_waddr;    // 写地址
    logic [7:0]  ram_wdata;    // 写数据
    logic        ram_we;       // 写使能

    // -------------------------------------------------------------------------
    // 状态标志观测
    // -------------------------------------------------------------------------
    logic        file_found;   // IMAGE.BIN 已找到
    logic        read_done;    // 文件读取完成

    // -------------------------------------------------------------------------
    // Modports
    // -------------------------------------------------------------------------

    // VGA Monitor (passive): 只读 VGA 信号
    modport vga_mon (
        input  vga_clk, vga_hs, vga_vs,
        input  vga_blank_n, vga_sync_n,
        input  vga_r, vga_g, vga_b
    );

    // FAT32 Scoreboard Monitor: 观测 RAM 写操作 + 状态标志
    modport fat32_mon (
        input  clk_50, rst_n,
        input  ram_waddr, ram_wdata, ram_we,
        input  file_found, read_done
    );

endinterface : sd_sys_if

`endif // SD_SYS_IF_SV
