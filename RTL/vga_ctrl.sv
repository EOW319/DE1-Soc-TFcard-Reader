module vga_ctrl (
    input  logic       clk,      // 25MHz Pixel Clock
    input  logic       rst_n,
    input  logic [7:0] img_data, // Data from RAM

    output logic [16:0] ram_addr, // Address to RAM (320x240)
    
    output logic       vga_hsync,
    output logic       vga_vsync,
    output logic       vga_blank_n,
    output logic       vga_sync_n,
    output logic [7:0] vga_r,
    output logic [7:0] vga_g,
    output logic [7:0] vga_b,
    output logic       vga_clk // Output clock for DAC
);

    // VGA Timing Constants (640x480 @ 60Hz, 25MHz)
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_TOTAL   = 800;

    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_TOTAL   = 525;

    logic [9:0] h_cnt;
    logic [9:0] v_cnt;
    logic [9:0] h_cnt_next;
    logic [9:0] v_cnt_next;

    assign vga_clk = clk;
    assign vga_sync_n = 1'b0; // Usually tied to 0 for generic VGA or ignored

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 0;
            v_cnt <= 0;
        end else begin
            if (h_cnt < H_TOTAL - 1) begin
                h_cnt <= h_cnt + 1;
            end else begin
                h_cnt <= 0;
                if (v_cnt < V_TOTAL - 1) begin
                    v_cnt <= v_cnt + 1;
                end else begin
                    v_cnt <= 0;
                end
            end
        end
    end

    always_comb begin
        h_cnt_next = h_cnt;
        v_cnt_next = v_cnt;

        if (h_cnt < H_TOTAL - 1) begin
            h_cnt_next = h_cnt + 1'b1;
        end else begin
            h_cnt_next = 0;
            if (v_cnt < V_TOTAL - 1)
                v_cnt_next = v_cnt + 1'b1;
            else
                v_cnt_next = 0;
        end
    end

    // Sync Signals
    assign vga_hsync = !((h_cnt >= H_VISIBLE + H_FRONT) && (h_cnt < H_VISIBLE + H_FRONT + H_SYNC));
    assign vga_vsync = !((v_cnt >= V_VISIBLE + V_FRONT) && (v_cnt < V_VISIBLE + V_FRONT + V_SYNC));
    
    // Active Area
    logic active_area;
    assign active_area = (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);
    assign vga_blank_n = active_area;

    // Memory Address Calculation
    // Scaling 320x240 image to 640x480 screen (2x zoom)
    // addr = (y/2) * 320 + (x/2)
    wire [8:0] mem_x = h_cnt_next[9:1]; // x / 2
    wire [7:0] mem_y = v_cnt_next[8:1]; // y / 2
    wire       active_area_next = (h_cnt_next < H_VISIBLE) && (v_cnt_next < V_VISIBLE);

    // img_ram 为同步读 RAM，rdata 会在下一个时钟边沿更新。
    // 因此这里将读地址提前一拍输出，使当前像素坐标与 img_data 对齐。
    // 320 * mem_y + mem_x
    // 320 = 256 + 64 = (mem_y << 8) + (mem_y << 6)
    assign ram_addr = (active_area_next) ? ({9'b0, mem_y} << 8) + ({9'b0, mem_y} << 6) + {8'b0, mem_x} : 17'd0;

    // Color Output
    // Assuming img_data is 8-bit color (RRRGGGBB or similar)
    // Let's assume standard 3-3-2 RGB for 8 bit: RRRGGGBB
    // R: [7:5], G: [4:2], B: [1:0]
    // Or Grayscale?
    // Let's assume Grayscale for simplicity if not specified, OR RGB332.
    // RGB332 is common.
    
    // Let's map RGB332 to 8-bit VGA DAC (usually 8 bit per channel on DE1-SoC, ADV7123 is 24-bit (3x10 actually, but used as 3x8)).
    always_comb begin
        if (active_area) begin
            // RGB 3-3-2 expansion
            vga_r = {img_data[7:5], img_data[7:5], img_data[7:6]}; // 3->8
            vga_g = {img_data[4:2], img_data[4:2], img_data[4:3]}; // 3->8
            vga_b = {img_data[1:0], img_data[1:0], img_data[1:0], img_data[1:0]}; // 2->8
        end else begin
            vga_r = 0;
            vga_g = 0;
            vga_b = 0;
        end
    end

endmodule
