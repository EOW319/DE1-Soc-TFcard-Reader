// =============================================================================
// sd_card_model.sv
// SD 卡行为模型 (Behavioral Model / BFM)
//
// 功能:
//   - 自动解析 sdclk 上升沿采样到的 48-bit 命令帧
//   - 根据 cmd_index 自动分发正确类型的响应
//   - CMD17 触发 DAT0 线 512B 数据块传输 (含 CRC16)
//   - 支持错误注入: inject_timeout / inject_crc_error / inject_wrong_cmd_idx
//   - ACMD41 支持多次 busy (busy_rounds 可配置)
//
// 响应映射:
//   CMD0  → 无响应 (进入 idle)
//   CMD8  → R7 (48-bit, echo VHS + check pattern)
//   CMD55 → R1 (48-bit)
//   ACMD41→ R3 (48-bit, 无 CRC7)
//   CMD2  → R2 (136-bit, 假 CID)
//   CMD3  → R6 (48-bit, RCA)
//   CMD7  → R1b (48-bit + busy 拉低 CMD 若干周期)
//   CMD16 → R1 (48-bit)
//   CMD17 → R1 + DAT0 数据块 (512B + CRC16)
//   其他  → R1 (默认)
//
// 接口: 直连 sdclk / sdcmd(三态, 通过 card_cmd_oe + card_cmd_out) /
//               sddat[3:0](通过 card_dat_oe + card_dat_out)
// =============================================================================
`ifndef SD_CARD_MODEL_SV
`define SD_CARD_MODEL_SV

module sd_card_model #(
    parameter int TOTAL_SECTORS = 4096,          // 磁盘总扇区数
    parameter int NCR_CYCLES    = 8,              // 命令到响应延迟 (sdclk 周期)
    parameter int RCA_VAL       = 32'h0001_0000   // 相对卡地址
) (
    input  logic        sdclk,
    // CMD 三态: 观测 + 驱动
    input  logic        sdcmd_obs,      // CMD 线观测 (来自三态仲裁结果)
    output logic        card_cmd_oe,    // 卡侧 CMD 输出使能
    output logic        card_cmd_out,   // 卡侧 CMD 输出值
    // DAT 三态 (仅 DAT[0] 实际使用)
    output logic [3:0]  card_dat_oe,
    output logic [3:0]  card_dat_out
);

    // =========================================================================
    // 内部存储: 磁盘镜像
    // =========================================================================
    logic [7:0] mem [0 : TOTAL_SECTORS*512-1];

    // =========================================================================
    // 错误注入控制 (通过 force 或 $value$plusargs 注入)
    // =========================================================================
    bit inject_timeout    = 0;  // 不响应任何命令
    bit inject_crc_error  = 0;  // 响应帧 CRC7 填错
    bit inject_wrong_cmd  = 0;  // 响应帧 cmd index 填错

    // ACMD41 busy 模拟: 前 acmd41_busy_rounds 次响应 bit31=0
    int unsigned acmd41_busy_rounds = 0;
    int unsigned acmd41_call_count  = 0;
    bit          app_cmd_flag       = 0;  // CMD55 后置 1，ACMD41 后清 0

    // =========================================================================
    // CRC7 计算函数 (多项式 x^7+x^3+1 = 0x09)
    // =========================================================================
    function automatic logic [6:0] calc_crc7(input logic [39:0] data);
        logic [6:0] crc = 7'h0;
        for (int i = 39; i >= 0; i--) begin
            logic inv = data[i] ^ crc[6];
            crc = {crc[5:0], 1'b0};
            if (inv) crc ^= 7'h09;
        end
        return crc;
    endfunction

    // CRC16 计算函数 (多项式 0x1021，用于数据块)
    function automatic logic [15:0] calc_crc16(input logic [7:0] blk[512]);
        logic [15:0] crc = 16'h0;
        for (int i = 0; i < 512; i++) begin
            for (int b = 7; b >= 0; b--) begin
                logic inv = blk[i][b] ^ crc[15];
                crc = {crc[14:0], 1'b0};
                if (inv) crc ^= 16'h1021;
            end
        end
        return crc;
    endfunction

    // =========================================================================
    // 主要行为: 命令解析 → 响应
    // =========================================================================
    initial begin
        card_cmd_oe  = 0;
        card_cmd_out = 1;
        card_dat_oe  = 4'h0;
        card_dat_out = 4'hF;
    end

    always begin
        // --- 步骤1: 等待 host start bit (sdcmd_obs = 0) ---
        @(negedge sdcmd_obs);

        fork
            begin : capture_cmd
                logic [47:0] frame;
                logic [5:0]  cmd_idx;
                logic [31:0] arg;
                logic [6:0]  crc7_rx;

                // 在后续 48 个 sdclk 上升沿采样
                for (int i = 47; i >= 0; i--) begin
                    @(posedge sdclk);
                    frame[i] = sdcmd_obs;
                end

                cmd_idx = frame[45:40];
                arg     = frame[39:8];
                crc7_rx = frame[7:1];

                // 等待 Ncr 周期
                repeat (NCR_CYCLES) @(posedge sdclk);

                if (!inject_timeout)
                    dispatch_response(cmd_idx, arg, frame);
            end
        join
    end

    // =========================================================================
    // 响应分发
    // =========================================================================
    task automatic dispatch_response(
        input logic [5:0]  cmd_idx,
        input logic [31:0] arg,
        input logic [47:0] rx_frame
    );
        case (cmd_idx)
            6'd0:  ; // GO_IDLE — 无响应
            6'd2:  send_r2(cmd_idx);
            6'd3:  send_r1(cmd_idx, RCA_VAL);
            6'd7:  send_r1b(cmd_idx, 32'h0);
            6'd8:  send_r7(cmd_idx, arg);     // echo VHS+check pat
            6'd16: send_r1(cmd_idx, 32'h0);
            6'd17: begin
                       send_r1(cmd_idx, 32'h0);
                       send_data_block(arg);   // arg = 扇区地址
                   end
            6'd41: begin
                       // ACMD41 (需在 CMD55 后)
                       acmd41_call_count++;
                       if (acmd41_call_count > acmd41_busy_rounds)
                           send_r3(32'hC000_0000); // bit31=1 (ready) + HCS
                       else
                           send_r3(32'h4000_0000); // bit31=0 (busy)
                       app_cmd_flag = 0;
                   end
            6'd55: begin
                       app_cmd_flag = 1;
                       send_r1(cmd_idx, 32'h0);
                   end
            default: send_r1(cmd_idx, 32'h0);
        endcase
    endtask

    // =========================================================================
    // 响应帧驱动 Tasks
    // =========================================================================

    // 在 sdclk 下降沿逐 bit 驱动 N-bit 数据到 CMD 线
    task automatic drive_cmd_bits(input logic [135:0] data, input int unsigned nbits);
        card_cmd_oe = 1;
        for (int i = nbits-1; i >= 0; i--) begin
            @(negedge sdclk);
            card_cmd_out = data[i];
        end
        @(negedge sdclk);
        card_cmd_out = 1;
        card_cmd_oe  = 0;
    endtask

    // R1: 48-bit 标准响应
    task automatic send_r1(input logic [5:0] cmd, input logic [31:0] status);
        logic [47:0] frame;
        logic [6:0]  crc;
        logic [39:0] crc_payload;
        logic [5:0]  cmd_to_send;

        // 准备发送的 cmd（可能被污染）
        cmd_to_send = inject_wrong_cmd ? ~cmd : cmd;
        
        // CRC 计算: {start=0, dir=1, cmd, status}
        crc_payload = {1'b0, 1'b1, cmd_to_send};
        crc_payload[31:0] = status;
        crc = inject_crc_error ? 7'h7F : calc_crc7({1'b0, 1'b1, cmd_to_send, status});
        
        // 构建响应帧: 显式指定每个字段的位置
        frame[47]    = 1'b0;              // start bit
        frame[46]    = 1'b1;              // direction bit (card to host)
        frame[45:40] = cmd_to_send;       // command index (关键!)
        frame[39:8]  = status;            // card status
        frame[7:1]   = crc;               // CRC7
        frame[0]     = 1'b1;              // end bit

        drive_cmd_bits({88'h0, frame}, 48);
    endtask

    // R1b: R1 + busy 信号 (DAT[0] 拉低)
    task automatic send_r1b(input logic [5:0] cmd, input logic [31:0] status);
        send_r1(cmd, status);
        // busy: DAT[0] 拉低 32 个 sdclk
        card_dat_oe  = 4'h1;
        card_dat_out = 4'h0;
        repeat (32) @(posedge sdclk);
        card_dat_oe  = 4'h0;
        card_dat_out = 4'hF;
    endtask

    // R2: 136-bit CID 响应 (无 CRC7 字段，CRC bits 全为 1)
    task automatic send_r2(input logic [5:0] cmd);
        // 假 CID: 全固定值
        logic [127:0] cid = 128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0;
        logic [135:0] frame;
        logic [5:0]  cmd_to_send;
        
        // R2 响应格式:start(0) + dir(1) + cmd_idx(6'b111111) + CID(128) + end_bit(1)
        cmd_to_send = inject_wrong_cmd ? ~cmd : cmd;
        frame[135]   = 1'b0;              // start bit
        frame[134]   = 1'b1;              // direction bit
        frame[133:128] = 6'b111111;       // cmd index (R2 always 0x3F)
        frame[127:0] = cid;               // CID
        drive_cmd_bits(frame, 136);
    endtask

    // R3: 48-bit OCR 响应 (CRC7 字段为全 1，无实际 CRC)
    task automatic send_r3(input logic [31:0] ocr);
        logic [47:0] frame;
        // R3 响应格式: start(0) + dir(1) + cmd_idx(6'b111111) + OCR(32) + crc_bits(7'h7F) + end(1)
        frame[47]    = 1'b0;              // start bit
        frame[46]    = 1'b1;              // direction bit (card to host)
        frame[45:40] = 6'b111111;         // cmd index (R3 always 0x3F)
        frame[39:8]  = ocr;               // OCR register
        frame[7:1]   = 7'h7F;             // CRC bits (all 1s, no real CRC)
        frame[0]     = 1'b1;              // end bit
        drive_cmd_bits({88'h0, frame}, 48);
    endtask

    // R6: 48-bit RCA 响应 (与 R1 格式相同)
    // R6 使用 send_r1(CMD3, RCA) 即可

    // R7: 48-bit 接口条件响应 (echo VHS + check pattern)
    task automatic send_r7(input logic [5:0] cmd, input logic [31:0] arg);
        // R7 格式: [39:20]=0, [19:16]=VHS(accepted voltage), [15:8]=check pattern, [7:0]=0
        logic [31:0] r7_arg;
        r7_arg = {12'h0, arg[19:16], arg[7:0], 8'h0}; // echo VHS + check pat
        send_r1(cmd, r7_arg);
    endtask

    // CMD17 数据块传输: 512B + CRC16 on DAT[0]
    task automatic send_data_block(input logic [31:0] sector);
        logic [7:0]  blk[512];
        logic [15:0] crc16;
        int          base;

        base = sector * 512;
        for (int i = 0; i < 512; i++)
            blk[i] = (base + i < $size(mem)) ? mem[base + i] : 8'hFF;

        crc16 = calc_crc16(blk);

        // 等待 2 个 sdclk 后开始发送 (Nac 最小延迟)
        repeat (2) @(posedge sdclk);

        // DAT[0] start bit
        card_dat_oe  = 4'h1;
        @(negedge sdclk); card_dat_out = 4'h0;

        // 512 字节数据 (MSB first, 1-bit 模式)
        for (int i = 0; i < 512; i++) begin
            for (int b = 7; b >= 0; b--) begin
                @(negedge sdclk);
                card_dat_out = {3'hF, blk[i][b]};
            end
        end

        // 16-bit CRC16
        for (int b = 15; b >= 0; b--) begin
            @(negedge sdclk);
            card_dat_out = {3'hF, crc16[b]};
        end

        // End bit
        @(negedge sdclk); card_dat_out = 4'hF;
        @(negedge sdclk);
        card_dat_oe = 4'h0;
    endtask

endmodule : sd_card_model

`endif // SD_CARD_MODEL_SV
