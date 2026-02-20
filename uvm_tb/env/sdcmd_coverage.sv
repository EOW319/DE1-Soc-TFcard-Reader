// =============================================================================
// sdcmd_coverage.sv
// Layer 1 — sdcmd_ctrl 功能覆盖率收集
//
// covergroup:
//   cg_cmd    : 覆盖所有 cmd index
//   cg_result : 覆盖 done / timeout / syntaxe 三种结果
//   cg_timing : clkdiv 和 precnt 范围分桶
//   cg_cross  : cmd × result 交叉覆盖
// =============================================================================
`ifndef SDCMD_COVERAGE_SV
`define SDCMD_COVERAGE_SV

class sdcmd_coverage extends uvm_subscriber #(sdcmd_mon_item);
    `uvm_component_utils(sdcmd_coverage)

    sdcmd_mon_item item_q[$];  // 暂存 analysis 数据
    sdcmd_txn      txn_q[$];   // 需配合 txn 信息 (通过 config_db 或 second port 传递)

    // 当前采样值 (供 covergroup 采样)
    bit [5:0]  cur_cmd;
    bit [15:0] cur_clkdiv;
    bit [15:0] cur_precnt;
    bit        cur_done;
    bit        cur_timeout;
    bit        cur_syntaxe;

    // -------------------------------------------------------------------------
    // Covergroups
    // -------------------------------------------------------------------------

    // 命令类型覆盖
    covergroup cg_cmd;
        cp_cmd : coverpoint cur_cmd {
            bins CMD0   = {6'd0};
            bins CMD2   = {6'd2};
            bins CMD3   = {6'd3};
            bins CMD7   = {6'd7};
            bins CMD8   = {6'd8};
            bins CMD16  = {6'd16};
            bins CMD17  = {6'd17};
            bins CMD41  = {6'd41};
            bins CMD55  = {6'd55};
        }
    endgroup : cg_cmd

    // 结果类型覆盖
    covergroup cg_result;
        cp_done    : coverpoint cur_done    { bins asserted = {1}; }
        cp_timeout : coverpoint cur_timeout { bins asserted = {1}; }
        cp_syntaxe : coverpoint cur_syntaxe { bins asserted = {1}; }
    endgroup : cg_result

    // 时序参数分桶覆盖
    covergroup cg_timing;
        cp_clkdiv : coverpoint cur_clkdiv {
            bins low  = {[1:10]};
            bins mid  = {[11:100]};
            bins high = {[101:200]};
        }
        cp_precnt : coverpoint cur_precnt {
            bins min_ncr = {[46:50]};
            bins mid_ncr = {[51:200]};
            bins max_ncr = {[201:500]};
        }
    endgroup : cg_timing

    // 交叉覆盖: cmd × result
    covergroup cg_cross;
        cp_cmd_x : coverpoint cur_cmd {
            bins CMD0  = {6'd0};  bins CMD2  = {6'd2};  bins CMD3  = {6'd3};
            bins CMD7  = {6'd7};  bins CMD8  = {6'd8};  bins CMD16 = {6'd16};
            bins CMD17 = {6'd17}; bins CMD41 = {6'd41}; bins CMD55 = {6'd55};
        }
        cp_res_x : coverpoint {cur_done, cur_timeout, cur_syntaxe} {
            bins done    = {3'b100};
            bins timeout = {3'b010};
            bins syntaxe = {3'b001};
        }
        cx_cmd_result : cross cp_cmd_x, cp_res_x;
    endgroup : cg_cross

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_cmd    = new();
        cg_result = new();
        cg_timing = new();
        cg_cross  = new();
    endfunction

    // Monitor 发布 mon_item 后调用此函数
    virtual function void write(sdcmd_mon_item t);
        cur_done    = t.got_done;
        cur_timeout = t.got_timeout;
        cur_syntaxe = t.got_syntaxe;
        cur_cmd     = t.cmd_frame[45:40];
        cur_clkdiv  = t.clkdiv;
        cur_precnt  = t.precnt;

        cg_cmd.sample();
        cg_result.sample();
        cg_timing.sample();
        cg_cross.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf("cg_cmd    coverage: %.1f%%", cg_cmd.get_coverage()),    UVM_NONE)
        `uvm_info("COV", $sformatf("cg_result coverage: %.1f%%", cg_result.get_coverage()), UVM_NONE)
        `uvm_info("COV", $sformatf("cg_timing coverage: %.1f%%", cg_timing.get_coverage()), UVM_NONE)
        `uvm_info("COV", $sformatf("cg_cross  coverage: %.1f%%", cg_cross.get_coverage()),  UVM_NONE)
    endfunction

endclass : sdcmd_coverage

`endif // SDCMD_COVERAGE_SV
