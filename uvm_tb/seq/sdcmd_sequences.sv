// =============================================================================
// sdcmd_sequences.sv
// Layer 1 — sdcmd_ctrl 序列库
//
// 序列列表:
//   sdcmd_single_seq    — 单条定向命令
//   sdcmd_init_seq      — 完整 SD 初始化序列 (CMD0→CMD8→55→41→2→3→7→16)
//   sdcmd_rand_seq      — N 条随机命令
//   sdcmd_error_seq     — 注入超时/CRC 错误
// =============================================================================
`ifndef SDCMD_SEQUENCES_SV
`define SDCMD_SEQUENCES_SV

// -----------------------------------------------------------------------------
// 单条定向命令序列
// -----------------------------------------------------------------------------
class sdcmd_single_seq extends uvm_sequence #(sdcmd_txn);
    `uvm_object_utils(sdcmd_single_seq)

    // 可在 test 中通过 seq.cmd_val = xxx 设置
    bit [5:0]  cmd_val  = 8;
    bit [31:0] arg_val  = 32'h000001AA;
    bit [15:0] clkdiv_val = 16'd4;
    bit [15:0] precnt_val = 16'd46;
    bit        exp_timeout = 0;
    bit        exp_crc_err = 0;

    function new(string name = "sdcmd_single_seq");
        super.new(name);
    endfunction

    task body();
        sdcmd_txn txn;
        txn = sdcmd_txn::type_id::create("txn");
        start_item(txn);
        txn.cmd           = cmd_val;
        txn.arg           = arg_val;
        txn.clkdiv        = clkdiv_val;
        txn.precnt        = precnt_val;
        txn.expect_timeout = exp_timeout;
        txn.expect_crc_err = exp_crc_err;
        finish_item(txn);
    endtask
endclass : sdcmd_single_seq

// -----------------------------------------------------------------------------
// 完整 SD 初始化序列
// CMD0 → CMD8 → CMD55+ACMD41(×N) → CMD2 → CMD3 → CMD7 → CMD16
// -----------------------------------------------------------------------------
class sdcmd_init_seq extends uvm_sequence #(sdcmd_txn);
    `uvm_object_utils(sdcmd_init_seq)

    // ACMD41 循环次数 (模拟卡未就绪场景)
    int unsigned acmd41_busy_rounds = 1;
    bit [15:0]   clkdiv_slow = 16'd256;  // 初始化低速时钟分频
    bit [15:0]   clkdiv_fast = 16'd4;    // 传输高速时钟分频
    bit [31:0]   rca = 32'h0001_0000;    // 假设 RCA = 0x0001

    function new(string name = "sdcmd_init_seq");
        super.new(name);
    endfunction

    // 辅助: 发送一条命令
    task send_cmd(int unsigned cmd, bit [31:0] arg,
                  bit [15:0] clkdiv, bit [15:0] precnt,
                  bit exp_to = 0);
        sdcmd_txn txn;
        txn = sdcmd_txn::type_id::create($sformatf("txn_cmd%0d", cmd));
        start_item(txn);
        txn.cmd            = cmd[5:0];
        txn.arg            = arg;
        txn.clkdiv         = clkdiv;
        txn.precnt         = precnt;
        txn.expect_timeout = exp_to;
        txn.expect_crc_err = 0;
        finish_item(txn);
    endtask

    task body();
        // CMD0 GO_IDLE (无响应，expect_timeout=1)
        send_cmd(0,  32'h0000_0000, clkdiv_slow, 16'd46, 1);

        // CMD8 SEND_IF_COND (R7)
        send_cmd(8,  32'h0000_01AA, clkdiv_slow, 16'd46, 0);

        // CMD55 + ACMD41 × acmd41_busy_rounds
        for (int i = 0; i < acmd41_busy_rounds; i++) begin
            send_cmd(55, 32'h0000_0000, clkdiv_slow, 16'd46, 0);  // APP_CMD
            send_cmd(41, 32'h4000_0000, clkdiv_slow, 16'd46, 0);  // HCS=1, busy
        end
        // 最后一轮 ACMD41 就绪 (power_up bit=1 由卡模型控制)
        send_cmd(55, 32'h0000_0000, clkdiv_slow, 16'd46, 0);
        send_cmd(41, 32'h4000_0000, clkdiv_slow, 16'd46, 0);

        // CMD2 ALL_SEND_CID (R2, 136-bit)
        send_cmd(2,  32'h0000_0000, clkdiv_slow, 16'd46, 0);

        // CMD3 SEND_RELATIVE_ADDR (R6)
        send_cmd(3,  32'h0000_0000, clkdiv_slow, 16'd46, 0);

        // CMD7 SELECT_CARD (R1b)  arg = RCA<<16
        send_cmd(7,  rca,           clkdiv_fast, 16'd46, 0);

        // CMD16 SET_BLOCKLEN=512
        send_cmd(16, 32'h0000_0200, clkdiv_fast, 16'd46, 0);

        `uvm_info("SEQ", "sdcmd_init_seq completed", UVM_MEDIUM)
    endtask
endclass : sdcmd_init_seq

// -----------------------------------------------------------------------------
// 随机命令序列 (N 条)
// -----------------------------------------------------------------------------
class sdcmd_rand_seq extends uvm_sequence #(sdcmd_txn);
    `uvm_object_utils(sdcmd_rand_seq)

    int unsigned num_txns = 20;

    function new(string name = "sdcmd_rand_seq");
        super.new(name);
    endfunction

    task body();
        sdcmd_txn txn;
        repeat (num_txns) begin
            txn = sdcmd_txn::type_id::create("txn");
            start_item(txn);
            if (!txn.randomize())
                `uvm_fatal("SEQ", "sdcmd_txn randomize() failed")
            txn.expect_timeout = 0;
            txn.expect_crc_err = 0;
            finish_item(txn);
        end
    endtask
endclass : sdcmd_rand_seq

// -----------------------------------------------------------------------------
// 错误注入序列
// -----------------------------------------------------------------------------
class sdcmd_error_seq extends uvm_sequence #(sdcmd_txn);
    `uvm_object_utils(sdcmd_error_seq)

    function new(string name = "sdcmd_error_seq");
        super.new(name);
    endfunction

    task body();
        sdcmd_txn txn;

        // 测试 timeout: 发 CMD8，卡模型不响应
        txn = sdcmd_txn::type_id::create("txn_timeout");
        start_item(txn);
        txn.cmd            = 6'd8;
        txn.arg            = 32'h000001AA;
        txn.clkdiv         = 16'd4;
        txn.precnt         = 16'd46;
        txn.expect_timeout = 1'b1;
        txn.expect_crc_err = 0;
        finish_item(txn);

        // 测试 syntaxe: 发 CMD8，卡模型回复 CRC 错误的响应
        txn = sdcmd_txn::type_id::create("txn_crc_err");
        start_item(txn);
        txn.cmd            = 6'd8;
        txn.arg            = 32'h000001AA;
        txn.clkdiv         = 16'd4;
        txn.precnt         = 16'd46;
        txn.expect_timeout = 0;
        txn.expect_crc_err = 1'b1;
        finish_item(txn);
    endtask
endclass : sdcmd_error_seq

`endif // SDCMD_SEQUENCES_SV
