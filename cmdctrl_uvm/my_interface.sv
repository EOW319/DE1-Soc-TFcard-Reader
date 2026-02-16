`ifndef SDCMD_IF__SV
`define SDCMD_IF__SV
interface sdcmd_if(input clk, input rstn);
    logic        cmd_start;
    logic [5:0]  cmd;
    logic [31:0] arg;
    logic [15:0] clkdiv;
    logic [15:0] precnt;

    logic          sdclk;
    wire           sdcmd;
    // config clk freq
    logic  [15:0] clkdiv;
    // user input signal
    logic         start;
    logic  [15:0] precnt;
    logic  [ 5:0] cmd;
    logic  [31:0] arg;
    // user output signal
    logic          busy;
    logic          done;
    logic          timeout;
    logic          syntaxe;
    logic  [31:0] resparg;
    logic         sdcmdoe;

    logic dut_sdcmd_out;    // from DUT
    logic tb_sdcmd_out;     // from SD card model
    assign sdcmd = sdcmdoe ? dut_sdcmd_out : tb_sdcmd_out;

    modport drv (
        input  clk,
        input  rstn,
        output start,
        output cmd,
        output arg,
        output clkdiv,
        output precnt,

        input   busy,
        input   done,
        input   timeout,
        input   syntaxe,
        input   resparg,
        input   sdcmdoe
    );

    modport mon (
        input clk,
        input rstn,
        input start,
        input cmd,
        input arg,
        input clkdiv,
        input precnt,
        input busy,
        input done,
        input timeout,
        input syntaxe,
        input resparg,
        input sdclk,
        input sdcmd,
        input sdcmdoe
    );

    modport resp (
        input  clk,
        input  sdclk,
        input  sdcmdoe,
        output tb_sdcmd_out
    );
endinterface //sdcmd_if()

`endif //SDCMD_IF__SV