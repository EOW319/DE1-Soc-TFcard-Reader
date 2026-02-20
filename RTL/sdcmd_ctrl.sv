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
    logic [5:0] cmd_reg;
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
    logic [7:0] resp_cnt;
    logic [47:0] resp_reg;
    logic [5:0] expected_resp_cmd_idx;

    always_comb begin
        unique case (cmd_reg)
            6'd2, 6'd41: expected_resp_cmd_idx = 6'h3F; // R2/R3 response expect cmd index = 0x3F
            default:      expected_resp_cmd_idx = cmd_reg;
        endcase
    end
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
            bit_cnt       <= 6'd0;
            precnt_reg    <= '0;
            timeout_cnt   <= '0;
            resp_cnt      <= 6'd0;
            cmd_reg       <= '0;
            resp_reg      <= '0;
        end
        else begin
            current_state <= next_state;
            crc7 <= CalcCrc7(crc_data);

            // --- S_LOAD_CMD: 锁存参数，初始化计数器 ---
            if (current_state == S_LOAD_CMD) begin
                precnt_reg  <= precnt;
                timeout_cnt <= '0;
                resp_cnt    <= (cmd == 6'd2) ? 8'd135 : 8'd47; // CMD2: R2(136b), 其他: 48b
                bit_cnt     <= 6'd47;       // S_SEND_CMD 中发送 48 bit (47 down to 0)
                cmd_reg     <= cmd;
                resp_reg    <= '0;          // 重置为全 0 (空闲状态)
            end

            // --- S_SEND_CMD: sdclk 上升沿递减 bit_cnt ---
            if (current_state == S_SEND_CMD && sdclk_q == 1'b0 && sdclk == 1'b1) begin
                bit_cnt <= bit_cnt - 6'd1;
            end

            // --- S_PRE_WAIT: 等待 precnt 个 sdclk 上升沿 ---
            if (current_state == S_PRE_WAIT && sdclk == 1'b1 && sdclk_q == 1'b0) begin
                if (precnt_reg != '0)
                    precnt_reg <= precnt_reg - 16'd1;
            end

            // --- S_WAIT_RESP: 等待 start bit，检测到后移位寄存 ---
            if (current_state == S_WAIT_RESP) begin
                if (sdclk == 1'b1 && sdclk_q == 1'b0) begin
                    timeout_cnt <= timeout_cnt + 8'd1;
                    if (sdcmdin == 1'b0) begin
                        // 检测到 start bit (0)，移位进 resp_reg
                        resp_reg <= {resp_reg[46:0], sdcmdin};
                    end
                end
            end else begin
                timeout_cnt <= '0;
            end

            // --- S_READ_RESP: 每个 sdclk 上升沿移位采样一个 bit ---
            if (current_state == S_READ_RESP && sdclk_q == 1'b0 && sdclk == 1'b1) begin
                // CMD2(R2,136-bit): 仅保留前 48-bit 响应头用于语法校验，其余 88-bit 只消耗不覆盖
                if ((cmd_reg != 6'd2) || (resp_cnt > 8'd88)) begin
                    resp_reg <= {resp_reg[46:0], sdcmdin};
                end
                resp_cnt <= resp_cnt - 8'd1;
            end

        end
    end

//--------------------------------------------
    always_comb begin
        busy     = 1'b0;
        done     = 1'b0;
        timeout  = 1'b0;
        syntaxe  = 1'b0;
        resparg  = '0;
        sdcmdoe  = 1'b0;
        sdcmdout = 1'b1;
        next_state = current_state;

        case (current_state)
            S_IDLE: begin
                if (start)
                    next_state = S_LOAD_CMD;
            end

            S_LOAD_CMD: begin
                busy    = 1'b1;
                next_state = S_SEND_CMD;
            end

            S_SEND_CMD: begin
                busy     = 1'b1;
                sdcmdoe  = 1'b1;
                sdcmdout = cmd_shift[bit_cnt];
                if (bit_cnt == 6'd0)
                    next_state = S_PRE_WAIT;
            end

            S_PRE_WAIT: begin
                busy = 1'b1;
                if (precnt_reg == '0)
                    next_state = S_WAIT_RESP;
            end

            S_WAIT_RESP: begin
                busy = 1'b1;
                if (sdclk_q == 1'b0 && sdclk == 1'b1) begin
                    if (sdcmdin == 1'b0)
                        next_state = S_READ_RESP;
                    else if (timeout_cnt >= TIMEOUT)
                        next_state = S_TIMEOUT;
                end
            end

            S_READ_RESP: begin
                busy = 1'b1;
                if (resp_cnt == 6'd0) begin
                    if (resp_reg[45:40] == expected_resp_cmd_idx)
                        next_state = S_DONE;
                    else
                        next_state = S_ERROR;
                end
            end

            S_DONE: begin
                done    = 1'b1;
                resparg = (cmd_reg == 6'd2) ? 32'h0 : resp_reg[39:8];
                if (start)
                    next_state = S_LOAD_CMD;
            end

            S_ERROR: begin
                syntaxe = 1'b1;
                if (start)
                    next_state = S_LOAD_CMD;
            end

            S_TIMEOUT: begin
                timeout = 1'b1;
                if (start)
                    next_state = S_LOAD_CMD;
            end

            default: begin
                // hold defaults
            end
        endcase
    end

endmodule

