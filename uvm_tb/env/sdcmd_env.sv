// =============================================================================
// sdcmd_env.sv
// Layer 1 — sdcmd_ctrl 验证环境
//
// 拓扑:
//   sdcmd_env
//   ├── sdcmd_host_agent   (active)  — driver + monitor + sequencer
//   ├── sdcmd_scoreboard             — 帧内容 + 输出检查
//   └── sdcmd_coverage               — 功能覆盖率
// =============================================================================
`ifndef SDCMD_ENV_SV
`define SDCMD_ENV_SV

class sdcmd_env extends uvm_env;
    `uvm_component_utils(sdcmd_env)

    sdcmd_host_agent  agent;
    sdcmd_scoreboard  scoreboard;
    sdcmd_coverage    coverage;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = sdcmd_host_agent::type_id::create("agent",      this);
        scoreboard = sdcmd_scoreboard::type_id::create("scoreboard", this);
        coverage   = sdcmd_coverage::type_id::create("coverage",     this);
        // Agent 默认为 ACTIVE 模式
        uvm_config_db #(uvm_active_passive_enum)::set(this, "agent", "is_active", UVM_ACTIVE);
    endfunction

    function void connect_phase(uvm_phase phase);
        // Monitor 的 analysis port 连接到 scoreboard 和 coverage
        agent.ap.connect(scoreboard.mon_export);
        agent.ap.connect(coverage.analysis_export);
        agent.txn_ap.connect(scoreboard.txn_fifo.analysis_export);
    endfunction

endclass : sdcmd_env

`endif // SDCMD_ENV_SV
