module sd_reader #( parameter [2:0] CLK_DIV = 3'd2,                                                   
                    parameter       SIMULATE = 0
)(  
    //top module interface
    input  logic clk,
    input  logic rst_n,
    
    //sd_file_reader interface
    input  logic rstart,
    input  logic [31:0] rsector,

    output logic rdone,
    output logic rbusy,
    output logic outen,
    output logic [7:0] outbyte,

    output logic sdclk,
    output logic [7:0] sddata,

    //sd card interface
    input  logic sddata0,
    inout wire sdcmd
);
    logic [15:0] precnt;
    logic [15:0] clkdiv;
    logic [15:0] cmd;
    logic [31:0] arg;
    logic busy;
    logic done;
    logic timeout;
    logic syntaxe;
    logic [31:0] resparg;
    logic sdcmdoe;
    logic [15:0] rca;
    logic ctrl_start;

    localparam [15:0] FASTCLKDIV = (16'd1 << CLK_DIV) ;
    localparam [15:0] SLOWCLKDIV = FASTCLKDIV * 16'd5;
    
    sdcmd_ctrl sdcmd_ctrl(
    .rstn(rst_n),
    .clk(clk),
    // SDcard signals (sdclk and sdcmd)
    .sdclk(sdclk),
    .sdcmd(sdcmd),
    // config clk freq
    .clkdiv(clkdiv),
    // user input signal
    .start(ctrl_start),
    .precnt(precnt),
    .cmd(cmd[5:0]),
    .arg(arg),
    // user output signal
    .busy(busy),
    .done(done),
    .timeout(timeout),
    .syntaxe(syntaxe),
    .resparg(resparg),
    .sdcmdoe(sdcmdoe)
    );

    task set_cmd;
        input [ 0:0] _start;
        input [15:0] _precnt;
        input [15:0] _cmd;
        input [31:0] _arg;
        begin
            ctrl_start <= _start;
            precnt     <= _precnt;
            cmd        <= _cmd;
            arg        <= _arg;
        end
    endtask    

    typedef enum logic [3:0] {
        CMD0,
        CMD8,
        CMD55,
        CMD41,
        CMD2,
        CMD3,
        CMD7,
        CMD16,
        CMD17,
        READING
    } sd_state_t;

    sd_state_t sdcmd_stat;
    logic [1:0] cmd_step; // 0: send cmd, 1: wait done


    //sdcard state machine
    always_ff @(posedge clk)begin
        if(~rst_n)begin
            set_cmd(0,0,0,0);
            clkdiv <= SLOWCLKDIV;
            rca    <= 16'h0000;
            sdcmd_stat <= CMD0;
            cmd_step <= 0;
            rbusy <= 1; // Initialization is busy
            rdone <= 0;
        end
        else begin
            // Default start to 0 to create a pulse, unless set_cmd sets it to 1
            if (cmd_step == 1 && ctrl_start) ctrl_start <= 0;

            case (sdcmd_stat)
                CMD0: begin
                    if (cmd_step == 0) begin
                        set_cmd(1, (SIMULATE?512:64000), 0, 'h00000000);
                        cmd_step <= 1;
                    end else if (done) begin
                         sdcmd_stat <= CMD8;
                         cmd_step <= 0;
                    end
                end
                
                CMD8: begin
                    if (cmd_step == 0) begin
                        set_cmd(1, 512, 8, 'h000001aa);
                        cmd_step <= 1;
                    end else if (done) begin
                         if (!timeout && !syntaxe)
                            sdcmd_stat <= CMD55;
                         else
                            sdcmd_stat <= CMD0; // Retry or Error handle
                         cmd_step <= 0;
                    end
                end
                
                CMD55: begin
                    if (cmd_step == 0) begin
                        set_cmd(1, 512, 55, 'h00000000); // CMD55
                        cmd_step <= 1;
                    end else if (done) begin
                         sdcmd_stat <= CMD41;
                         cmd_step <= 0;
                    end
                end

                CMD41: begin
                    if (cmd_step == 0) begin
                        set_cmd(1, 256, 41, 'h40100000); // ACMD41 with HCS bit
                        cmd_step <= 1;
                    end else if (done) begin
                         if (resparg[31] == 1'b1) begin // Card Power Up Status Bit
                             sdcmd_stat <= CMD2;
                         end else begin
                             sdcmd_stat <= CMD55; // Not ready, repeat CMD55+ACMD41
                         end
                         cmd_step <= 0;
                    end
                end

                CMD2: begin
                    if (cmd_step == 0) begin
                        set_cmd(1, 256, 2, 'h00000000);
                        cmd_step <= 1;
                    end else if (done) begin
                         sdcmd_stat <= CMD3;
                         cmd_step <= 0;
                    end
                end

                CMD3: begin
                    if (cmd_step == 0) begin
                        set_cmd(1, 256, 3, 'h00000000);
                        cmd_step <= 1;
                    end else if (done) begin
                         rca <= resparg[31:16];
                         sdcmd_stat <= CMD7;
                         cmd_step <= 0;
                    end
                end

                CMD7: begin
                    if (cmd_step == 0) begin
                        set_cmd(1, 256, 7, {rca, 16'h0});
                        cmd_step <= 1;
                    end else if (done) begin
                         clkdiv <= FASTCLKDIV; // Switch to fast clock
                         sdcmd_stat <= CMD16;
                         cmd_step <= 0;
                    end
                end

                CMD16: begin
                    if (cmd_step == 0) begin
                        set_cmd(1, (SIMULATE?512:64000), 16, 'h00000200); // Block len 512
                        cmd_step <= 1;
                    end else if (done) begin
                         sdcmd_stat <= CMD17;
                         cmd_step <= 0;
                         rbusy <= 0; // Initialization done
                    end
                end

                CMD17: begin
                    // Idle state waiting for read request
                    if (rstart) begin
                        if (cmd_step == 0) begin
                            set_cmd(1, 0, 17, rsector);
                            rbusy <= 1;
                            rdone <= 0;
                            cmd_step <= 1;
                        end else if (done) begin
                             // Command sent, now wait for data
                             sdcmd_stat <= READING;
                             cmd_step <= 0;
                        end
                    end else begin
                        cmd_step <= 0;
                        rbusy <= 0;
                    end
                end

                READING: begin
                     // Waiting for data reading to complete
                     if (rdone) begin
                         sdcmd_stat <= CMD17;
                         rbusy <= 0;
                     end
                end
                
                default: sdcmd_stat <= CMD0;
            endcase
        end
    end

    // Data reading logic
    logic [3:0] bit_cnt;
    logic [9:0] byte_cnt;
    logic [7:0] shift_reg;
    logic       reading_active;
    logic       sdclk_d;
    logic       sdclk_rise;

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            sdclk_d <= 1;
        end else begin
            sdclk_d <= sdclk;
        end
    end
    assign sdclk_rise = (sdclk == 1 && sdclk_d == 0);

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            reading_active <= 0;
            bit_cnt <= 0;
            byte_cnt <= 0;
            outen <= 0;
            outbyte <= 0;
            rdone <= 0; // rdone is also used in the state machine above
        end else begin
            outen <= 0; // Default
            
            // Only active when main state machine is in READING
            if (sdcmd_stat == READING) begin
                if (!reading_active) begin
                    // Wait for start bit (0)
                    // Must detect start bit on sdclk rising edge to be synchronous
                    if (sdclk_rise && sddata0 == 0) begin
                        reading_active <= 1;
                        bit_cnt <= 7;
                        byte_cnt <= 0;
                        rdone <= 0;
                    end
                end else if (sdclk_rise) begin
                    // Reading data on rising edge of sdclk
                    
                    if (byte_cnt < 512) begin
                        shift_reg[bit_cnt] <= sddata0;
                        if (bit_cnt == 0) begin
                            bit_cnt <= 7;
                            byte_cnt <= byte_cnt + 1;
                            outen <= 1;
                            // shift_reg is not fully updated at this clock edge for bit 0
                            // so we should output {shift_reg[7:1], sddata0}
                            outbyte <= {shift_reg[7:1], sddata0}; 
                        end else begin
                            bit_cnt <= bit_cnt - 1;
                        end
                    end else begin
                        // CRC (16 bits) + End bit - ignore for now or consume cycles
                        // 16 bits CRC = 2 bytes. 
                        if (byte_cnt < 514) begin // 512, 513 for CRC
                             if (bit_cnt == 0) begin
                                bit_cnt <= 7;
                                byte_cnt <= byte_cnt + 1;
                             end else begin
                                bit_cnt <= bit_cnt - 1;
                             end
                        end else begin
                             // Done
                             reading_active <= 0;
                             rdone <= 1;
                        end
                    end
                end
            end else begin
                // Not in READING state
                reading_active <= 0;
                rdone <= 0;
            end
        end
    end

endmodule
