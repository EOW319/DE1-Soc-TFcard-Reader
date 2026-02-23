module top_sd_vga (
    input  logic        CLOCK_50,
    input  logic [3:0]  KEY,      // KEY[0] is reset_n
    
    // SD Card Interface
    output logic        SD_CLK,
    inout  wire         SD_CMD,
    inout  wire  [3:0]  SD_DAT,   // SD_DAT[0] used as input sddata0
    output logic        SD_CD,
    
    // VGA Interface
    output logic        VGA_CLK,
    output logic        VGA_HS,
    output logic        VGA_VS,
    output logic        VGA_BLANK_N,
    output logic        VGA_SYNC_N,
    output logic [7:0]  VGA_R,
    output logic [7:0]  VGA_G,
    output logic [7:0]  VGA_B,

    // LED/HEX for Debug
    output logic [9:0]  LEDR,
    output logic [6:0]  HEX0
);

    // Internal Signals
    logic        clk_25 = 1'b0;
    logic        rst_n;
    assign rst_n = KEY[0];
    assign SD_CD = 1'b0; // Assume SD card is always present for simplicity
    
    // Clock Generation: 50MHz -> 25MHz
    // Keep divider running during reset so submodules with synchronous reset
    // still receive clock edges while rst_n is low.
    always_ff @(posedge CLOCK_50) begin
        clk_25 <= ~clk_25;
    end

    // SD Reader Interface Signals
    logic        sd_rstart;
    logic [31:0] sd_rsector;
    logic        sd_rdone;
    logic        sd_rbusy;
    logic        sd_outen;
    logic [7:0]  sd_outbyte;
    logic        sd_clk_out;
    
    logic debug_syntaxe;
    logic debug_timeout;
    // SD Card Physical Interface Wiring
    assign SD_CLK = sd_clk_out;
    // SD_DAT[0] is input (MISO/Data0)
    // Pull-up on unused SD_DAT lines? Usually handled by board pull-ups.
    // We drive SD_DAT[1:3] to Z?
    assign SD_DAT[3:1] = 3'b1;
    
    // SD Reader Module
    // Note: Assuming SD_DAT[0] is the data line from card
    sd_reader #(.CLK_DIV(3'd2), .SIMULATE(0)) u_sd_reader (
        .clk(clk_25),
        .rst_n(rst_n),
        .rstart(sd_rstart),
        .rsector(sd_rsector),
        .rdone(sd_rdone),
        .rbusy(sd_rbusy),
        .outen(sd_outen),
        .outbyte(sd_outbyte),
        .sdclk(sd_clk_out),
        .sddata0(SD_DAT[0]),
        .sdcmd(SD_CMD),
        .debug_syntaxe(debug_syntaxe),
        .debug_timeout(debug_timeout)
    );

    // RAM Interface
    logic [16:0] ram_waddr;
    logic [7:0]  ram_wdata;
    logic        ram_we;
    logic [16:0] ram_raddr;
    logic [7:0]  ram_rdata;

    // File Reader Logic
    logic        file_found;
    logic        read_done;
    logic [3:0]  state_debug;

    sd_file_reader u_file_reader (
        .clk(clk_25),
        .rst_n(rst_n),
        .rstart(sd_rstart),
        .rsector(sd_rsector),
        .rbusy(sd_rbusy),
        .rdone(sd_rdone),
        .outen(sd_outen),
        .outbyte(sd_outbyte),
        .ram_addr(ram_waddr),
        .ram_wdata(ram_wdata),
        .ram_we(ram_we),
        .file_found(file_found),
        .read_done(read_done),
        .state_debug(state_debug)
    );

    // RAM for Image Buffer
    img_ram u_ram (
        .clk(clk_25),
        .we(ram_we),
        .waddr(ram_waddr),
        .wdata(ram_wdata),
        .raddr(ram_raddr),
        .rdata(ram_rdata)
    );

    // VGA Controller
    vga_ctrl u_vga (
        .clk(clk_25),
        .rst_n(rst_n),
        .img_data(ram_rdata),
        .ram_addr(ram_raddr),
        .vga_hsync(VGA_HS),
        .vga_vsync(VGA_VS),
        .vga_blank_n(VGA_BLANK_N),
        .vga_sync_n(VGA_SYNC_N),
        .vga_r(VGA_R),
        .vga_g(VGA_G),
        .vga_b(VGA_B),
        .vga_clk(VGA_CLK)
    );

    // Debug LEDs
    assign LEDR[0] = file_found;
    assign LEDR[1] = read_done;
    assign LEDR[2] = sd_rbusy;
    assign LEDR[3] = sd_rdone;
    assign LEDR[4] = 1'b0;
    assign LEDR[5] = debug_syntaxe;
    assign LEDR[6] = debug_timeout;
    assign LEDR[9:7] = 3'b0;
    

    // 7-segment display for state
    // Simple hex decoder for state_debug
    function logic [6:0] seg7(input [3:0] hex);
        case (hex)
            4'h0: seg7 = 7'b1000000;
            4'h1: seg7 = 7'b1111001;
            4'h2: seg7 = 7'b0100100;
            4'h3: seg7 = 7'b0110000;
            4'h4: seg7 = 7'b0011001;
            4'h5: seg7 = 7'b0010010;
            4'h6: seg7 = 7'b0000010;
            4'h7: seg7 = 7'b1111000;
            4'h8: seg7 = 7'b0000000;
            4'h9: seg7 = 7'b0010000;
            4'hA: seg7 = 7'b0001000;
            4'hB: seg7 = 7'b0000011;
            4'hC: seg7 = 7'b1000110;
            4'hD: seg7 = 7'b0100001;
            4'hE: seg7 = 7'b0000110;
            4'hF: seg7 = 7'b0001110;
            default: seg7 = 7'b1111111;
        endcase
    endfunction

    assign HEX0 = seg7(state_debug);

endmodule
