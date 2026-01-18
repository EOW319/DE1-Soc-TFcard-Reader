module sdcmd_ctrl (
    input  logic         rstn,
    input  logic         clk,
    // SDcard signals (sdclk and sdcmd)
    output logic          sdclk,
    inout  wire           sdcmd,
    // config clk freq
    input  logic  [15:0] clkdiv,
    // user input signal
    input  logic         start,
    input  logic  [15:0] precnt,
    input  logic  [ 5:0] cmd,
    input  logic  [31:0] arg,
    // user output signal
    output logic          busy,
    output logic          done,
    output logic          timeout,
    output logic          syntaxe,
    output logic  [31:0] resparg,
    output logic         sdcmdoe
);

//--------------------------------------------
    localparam [7:0] TIMEOUT = 8'd250;

    typedef enum logic [3:0] {
    S_IDLE,
    S_LOAD_CMD,
    S_SEND_CMD,
    S_PRE_WAIT,
    S_WAIT_RESP,
    S_READ_RESP,
    S_DONE,
    S_ERROR,
    S_TIMEOUT
    } state_t;
    logic [47:0] cmd_shift;
    logic [3:0] current_state, next_state;

    logic sdcmdout = 1'b1;

    // sdcmd tri-state driver
    assign sdcmd = sdcmdoe ? sdcmdout : 1'bz;
    logic sdcmdin;
    assign sdcmdin = sdcmdoe ? 1'b1 : sdcmd;

    logic [15:0] clkcnt;


    //--------------------CRC generation------------------------
    logic [6:0] crc7;
    logic [39:0] crc_data;
    assign crc_data = {1'b0, 1'b1, cmd, arg};
    //cmd_shift structure: (1b start bit:0) + (1b transmission bit:1) + (6b cmd index) + (32b argument index) +(7bit crc7) + (1b end bit:1)
    assign cmd_shift = {1'b0,1'b1,cmd[5:0],arg[31:0],crc7[6:0],1'b1};
    function automatic logic [6:0] CalcCrc7(input logic [39:0] crc_data);
        int i;
        logic [6:0] crc;
        begin
            crc = 7'b0;
            for (i = 39; i>=0 ; i--) begin
                if (crc_data[i] ^ crc[6]) begin
                    crc = {crc[5:0],1'b0} ^ 7'h9;
                end
                else begin
                    crc = {crc[5:0], 1'b0};
                end
            end
            return crc;
        end
    endfunction

//--------------------------------------------
    logic sdclk_q;
    logic [5:0] bit_cnt;
    logic [15:0] precnt_reg;
    logic [7:0] timeout_cnt;
    logic [5:0] resp_cnt;
    logic [47:0] resp_reg;
//-----------------------SDCLK divider---------------------
    
    always_ff @(posedge clk) begin : clk_divider
        if (!rstn) begin
            clkcnt <= '0;
            sdclk <= '1;
            sdclk_q <= '1;
        end
        else begin
            sdclk_q <= sdclk;
            if (clkcnt == clkdiv) begin
                clkcnt <= 16'd0;
                sdclk  <= ~sdclk;
            end else begin
                    clkcnt <= clkcnt + 16'd1;
            end
        end
    end

//-----------------------FSM---------------------

    always_ff @(posedge clk) begin
        if (!rstn) begin
            current_state <= S_IDLE;
            bit_cnt <= 6'd46;
            precnt_reg <= precnt;
            timeout_cnt <= '0;
            resp_cnt <= 6'd46;
        end
        else begin
            current_state <= next_state;
            crc7 <= CalcCrc7(crc_data);
            
            if(current_state == S_LOAD_CMD)begin
                precnt_reg <= precnt;
                timeout_cnt <= 0;
                resp_cnt <= 6'd46;
                bit_cnt <= 6'd47;
            end
            
            if (current_state == S_SEND_CMD && (sdclk_q == '0 && sdclk == '1))begin
                bit_cnt <= bit_cnt - 1;
            end

            if (current_state == S_PRE_WAIT) begin
                if (sdclk == 1 && sdclk_q == 0) begin
                    if (precnt_reg != 0) begin
                        precnt_reg <= precnt_reg - 1;
                    end
                end
            end

            if (current_state == S_WAIT_RESP) begin   
                if (sdclk == 1 && sdclk_q == 0) begin
                    timeout_cnt <= timeout_cnt + 1;
                end
            end else begin
                timeout_cnt <= 0;
            end
            if (next_state == S_READ_RESP) begin
                resp_reg[47] <= sdcmdin;
                resp_reg[0] <= 1;
            end
            if (current_state == S_READ_RESP && (sdclk_q == '0 && sdclk == '1))begin
                if (resp_cnt != 0) begin
                    resp_cnt <= resp_cnt - 1;
                end
                resp_reg[resp_cnt] <= sdcmdin;
            end
            
        end
    end

//--------------------------------------------
    /*
    busy,
    done,
    timeout,
    syntaxe,
    resparg
    */
    always_comb begin
        busy = 0; 
        done = 0;
        timeout = 0;
        syntaxe = 0;
        resparg = '0;
        sdcmdoe = 0;
        sdcmdout = 1;
        next_state = current_state;
        
        case (current_state)
            S_IDLE: begin
            if (start) begin
                next_state = S_LOAD_CMD;
            end
            end

            S_LOAD_CMD:begin
                busy = 1;
                sdcmdoe = 0;
                next_state = S_SEND_CMD;
            end

            S_SEND_CMD: begin
                busy = 1;
                sdcmdoe = 1;
                sdcmdout = cmd_shift[bit_cnt];
                if(bit_cnt == 0) begin
                    next_state = S_PRE_WAIT;
                end
            end
            
            S_PRE_WAIT:begin
                busy = 1;
                if (precnt_reg == 0) begin
                    next_state = S_WAIT_RESP;
                end
            end

            S_WAIT_RESP: begin
                busy = 1;
                if (sdclk_q == 1'b0 && sdclk == 1'b1) begin
                    if (sdcmdin == 1'b0) begin
                        next_state = S_READ_RESP;
                    end
                    else if (timeout_cnt >= TIMEOUT) begin
                        next_state = S_TIMEOUT;
                    end
                end
            end
            
            S_READ_RESP:begin
                busy = 1;

                if (resp_cnt == 0) begin
                    if (resp_reg[45:40] == cmd) begin
                        next_state = S_DONE;
                    end
                    else next_state = S_ERROR;
                end
            end
            
            S_DONE: begin
                done = 1;
                busy = 0;
                resparg = resp_reg[39:8];
                if (start) begin
                    next_state = S_LOAD_CMD;
                end
            end

            S_ERROR:begin
                syntaxe = 1;
                done = 0;
                busy = 0;
                if (start) begin
                    next_state = S_LOAD_CMD;
                end
            end

            S_TIMEOUT: begin
                timeout = 1;
                done = 0;
                busy = 0;
                if (start) begin
                    next_state = S_LOAD_CMD;
                end
            end
            
            default: begin
                busy = 0; 
                done = 0;
                timeout = 0;
                syntaxe = 0;
                resparg = 0;
                sdcmdoe = 0;
                sdcmdout = 1;
            end
        endcase
    end



endmodule

