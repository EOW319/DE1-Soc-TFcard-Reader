// =============================================================================
// sd_reader_env.sv
// Layer 2 — sd_reader 验证环境
//
// 拓扑:
//   sd_reader_env
//   ├── sd_reader_host_agent  (active)  — driver + monitor + sequencer
//   └── sd_reader_scoreboard            — 512B 扇区数据比对
// =============================================================================
`ifndef SD_READER_ENV_SV
`define SD_READER_ENV_SV

class sd_reader_env extends uvm_env;
    `uvm_component_utils(sd_reader_env)

    sd_reader_host_agent  agent;
    sd_reader_scoreboard  scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = sd_reader_host_agent::type_id::create("agent",      this);
        scoreboard = sd_reader_scoreboard::type_id::create("scoreboard", this);
        uvm_config_db #(uvm_active_passive_enum)::set(this, "agent", "is_active", UVM_ACTIVE);
    endfunction

    function void connect_phase(uvm_phase phase);
        // Monitor AP → Scoreboard
        agent.ap.connect(scoreboard.mon_export);
    endfunction

endclass : sd_reader_env

`endif // SD_READER_ENV_SV
