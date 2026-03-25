module top_sd_vga #(
    parameter bit SD_READER_SIMULATE = 0
) (
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
    logic [19:0] por_cnt = '0;
    logic        por_done = 1'b0;
    assign SD_CD = 1'b0; // Assume SD card is always present for simplicity

    assign rst_n = KEY[0] & por_done;

    // Hold the design in reset for a short time after configuration so the SD card
    // sees idle clocks with CMD/DAT high before the first command.
    always_ff @(posedge CLOCK_50) begin
        if (!KEY[0]) begin
            por_cnt <= '0;
            por_done <= 1'b0;
        end else if (!por_done) begin
            por_cnt <= por_cnt + 20'd1;
            if (&por_cnt) begin
                por_done <= 1'b1;
            end
        end
    end
    
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
    (* keep *) logic [3:0]  sd_state_debug;
    (* preserve *) logic [5:0] sd_dbg_resp_cmd_idx;
    (* preserve *) logic [6:0] sd_dbg_resp_crc;
    (* preserve *) logic [6:0] sd_dbg_expected_resp_crc;
    (* preserve *) logic       sd_dbg_cmd_idx_match;
    (* preserve *) logic       sd_dbg_crc_match;
    (* preserve *) logic       sd_dbg_resp_check_fire;
    
    logic debug_syntaxe;
    logic debug_timeout;
    (* preserve *) logic debug_syntaxe_latched = 1'b0;
    (* preserve *) logic debug_timeout_latched = 1'b0;
    // SD Card Physical Interface Wiring
    assign SD_CLK = sd_clk_out;
    // SD_DAT[0] is input (MISO/Data0)
    // In 1-bit SD mode the unused DAT[3:1] lines stay released and rely on pull-ups.
    assign SD_DAT[3:1] = 3'bzzz;
    
    // SD Reader Module
    // Note: Assuming SD_DAT[0] is the data line from card
    sd_reader #(.CLK_DIV(3'd2), .SIMULATE(SD_READER_SIMULATE)) u_sd_reader (
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
        .debug_timeout(debug_timeout),
        .state_debug(sd_state_debug),
        .dbg_resp_cmd_idx(sd_dbg_resp_cmd_idx),
        .dbg_resp_crc(sd_dbg_resp_crc),
        .dbg_expected_resp_crc(sd_dbg_expected_resp_crc),
        .dbg_cmd_idx_match(sd_dbg_cmd_idx_match),
        .dbg_crc_match(sd_dbg_crc_match),
        .dbg_resp_check_fire(sd_dbg_resp_check_fire)
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
    logic [3:0]  file_state_debug;

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
        .state_debug(file_state_debug)
    );

    always_ff @(posedge clk_25) begin
        if (!rst_n) begin
            debug_syntaxe_latched <= 1'b0;
            debug_timeout_latched <= 1'b0;
        end else begin
            if (debug_syntaxe) begin
                debug_syntaxe_latched <= 1'b1;
            end
            if (debug_timeout) begin
                debug_timeout_latched <= 1'b1;
            end
        end
    end

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
    assign LEDR[5] = debug_syntaxe_latched;
    assign LEDR[6] = debug_timeout_latched;
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

    assign HEX0 = seg7(sd_rbusy ? sd_state_debug : file_state_debug);

endmodule
