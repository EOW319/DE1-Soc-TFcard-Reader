module img_ram (
    input  logic        clk,
    input  logic        we,
    input  logic [16:0] waddr,
    input  logic [7:0]  wdata,
    input  logic [16:0] raddr,
    output logic [7:0]  rdata
);

    // 320x240 = 76800 bytes
    // Using simple dual port RAM inference
    // Assuming same clock for read/write for simplicity (25MHz)
    
    (* ramstyle = "M10K" *) reg [7:0] mem [0:76799];

    always_ff @(posedge clk) begin
        if (we) begin
            mem[waddr] <= wdata;
        end
        rdata <= mem[raddr];
    end

endmodule
