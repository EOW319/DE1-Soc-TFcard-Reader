// =============================================================================
// sdcmd_scoreboard.sv
// Layer 1 — sdcmd_ctrl 检查器
//
// 检查项:
//   [命令帧]  start_bit=0, trans_bit=1, cmd_index, arg, CRC7, end_bit=1
//   [响应帧]  start_bit=0, trans_bit=0, cmd_index_echo(R1/R6/R7),
//             CRC7(R1/R6/R7 有效, R2/R3 忽略), end_bit=1
//   [DUT 输出] done/timeout/syntaxe 与 txn 预期一致
//              resparg = resp_frame[39:8]
// =============================================================================
`ifndef SDCMD_SCOREBOARD_SV
`define SDCMD_SCOREBOARD_SV

class sdcmd_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(sdcmd_scoreboard)

    // 接收 Monitor 发布的观测项
    uvm_analysis_imp #(sdcmd_mon_item, sdcmd_scoreboard) mon_export;
    // 接收 Driver 通过 TLM FIFO 传递的期望 txn
    uvm_tlm_analysis_fifo #(sdcmd_txn) txn_fifo;

    // 统计计数器
    int unsigned pass_cnt;
    int unsigned fail_cnt;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon_export = new("mon_export", this);
        txn_fifo   = new("txn_fifo",  this);
        pass_cnt   = 0;
        fail_cnt   = 0;
    endfunction

    // Monitor 每完成一次命令/响应交互，调用此函数
    function void write(sdcmd_mon_item item);
        sdcmd_txn txn;
        
        // Skip spurious monitor items (timeout frames from startup)
        if (item.cmd_frame == 48'h0 && item.resp_frame == 48'h0) begin
            `uvm_info("SB", "Skipping spurious monitor item (no valid frames)", UVM_HIGH)
            return;
        end
        
        if (!txn_fifo.try_get(txn)) begin
            // Check if this might be a spurious frame during initialization
            if (!item.resp_valid) begin
                `uvm_info("SB", "Skipping invalid monitor item (resp_valid=0)", UVM_HIGH)
                return;
            end
            `uvm_error("SB", $sformatf("No expected txn in FIFO when monitor item arrived (cmd_frame=0x%012X, resp_frame=0x%012X)", 
                                       item.cmd_frame, item.resp_frame))
            return;
        end
        check_item(txn, item);
    endfunction

    // -------------------------------------------------------------------------
    // 核心检查函数
    // -------------------------------------------------------------------------
    function void check_item(sdcmd_txn txn, sdcmd_mon_item item);
        bit err = 0;
        // --- 检查dut收到的命令和参数是否与 txn 预期一致 ---
        if (item.cmd_frame [45:40] !== txn.cmd || item.cmd_frame[39:8] !== txn.arg) begin
            `uvm_error("SB", $sformatf("Monitor item cmd/arg mismatch: got CMD%0d arg=0x%08X, expected CMD%0d arg=0x%08X",
                       item.cmd_frame[45:40], item.cmd_frame[39:8], txn.cmd, txn.arg))
            err = 1;
        end

        // --- 命令帧检查 ---
        // [47]   start bit = 0
        if (item.cmd_frame[47] !== 1'b0) begin
            `uvm_error("SB", $sformatf("CMD frame start bit != 0: frame=0x%012X", item.cmd_frame))
            err = 1;
        end
        // [46]   transmission bit = 1 (host → card)
        if (item.cmd_frame[46] !== 1'b1) begin
            `uvm_error("SB", $sformatf("CMD frame trans bit != 1: frame=0x%012X", item.cmd_frame))
            err = 1;
        end
        // [45:40] cmd index
        if (item.cmd_frame[45:40] !== txn.cmd) begin
            `uvm_error("SB", $sformatf("CMD frame index mismatch: got %0d, exp %0d",
                       item.cmd_frame[45:40], txn.cmd))
            err = 1;
        end
        // [39:8] arg
        if (item.cmd_frame[39:8] !== txn.arg) begin
            `uvm_error("SB", $sformatf("CMD frame arg mismatch: got 0x%08X, exp 0x%08X",
                       item.cmd_frame[39:8], txn.arg))
            err = 1;
        end
        // [7:1]  CRC7 — TODO: 调用 CalcCrc7 参考模型比对
        // [0]    end bit = 1
        if (item.cmd_frame[0] !== 1'b1) begin
            `uvm_error("SB", $sformatf("CMD frame end bit != 1: frame=0x%012X", item.cmd_frame))
            err = 1;
        end

        // --- DUT 输出检查 ---
        if (txn.expect_timeout) begin
            if (!item.got_timeout) begin
                `uvm_error("SB", "Expected timeout but DUT did not assert timeout")
                err = 1;
            end
        end else if (txn.expect_crc_err) begin
            if (!item.got_syntaxe) begin
                `uvm_error("SB", "Expected syntaxe but DUT did not assert syntaxe")
                err = 1;
            end
        end else begin
            if (!item.got_done) begin
                `uvm_error("SB", $sformatf("Expected done but DUT asserted timeout or syntaxe (done=%0b timeout=%0b syntaxe=%0b, dut_resp_reg[45:40]=0x%0h)",
                           item.got_done, item.got_timeout, item.got_syntaxe, item.dut_resp_cmd_idx_dbg))
                err = 1;
            end
        end

        // --- resparg 检查 (仅在 done 时有效, 非 R2/R3, 且有 bus-level 响应帧时) ---
        if (item.got_done && item.resp_valid && txn.cmd !== 6'd2 && txn.cmd !== 6'd41
            && item.resp_frame != 48'h0) begin
            if (item.resparg !== item.resp_frame[39:8]) begin
                `uvm_error("SB", $sformatf("resparg mismatch: DUT=0x%08X, resp_frame[39:8]=0x%08X",
                           item.resparg, item.resp_frame[39:8]))
                err = 1;
            end
        end

        if (!err) begin
            pass_cnt++;
            `uvm_info("SB", $sformatf("PASS [%0d]: CMD%0d arg=0x%08X", pass_cnt, txn.cmd, txn.arg), UVM_MEDIUM)
        end else begin
            fail_cnt++;
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SB", $sformatf("Scoreboard summary: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt), UVM_NONE)
        if (fail_cnt > 0)
            `uvm_error("SB", "Scoreboard detected FAILURES")
    endfunction

endclass : sdcmd_scoreboard

`endif // SDCMD_SCOREBOARD_SV
