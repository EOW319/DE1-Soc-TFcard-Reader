// =============================================================================
// sdcmd_tests.sv
// Layer 1 — sdcmd_ctrl 测试用例
//
// 测试列表:
//   sdcmd_base_test      — 基础 test class，创建 env，提供公共 task
//   sdcmd_smoke_test     — CMD8 + R7 响应验证 (smoke test)
//   sdcmd_init_test      — 完整 SD 初始化序列
//   sdcmd_timeout_test   — 卡不响应，验证 timeout 路径
//   sdcmd_crc_error_test — 注入 CRC 错误，验证 syntaxe 路径
//   sdcmd_r2_test        — CMD2 136-bit 长响应接收
//   sdcmd_rand_test      — 随机命令 + 覆盖率驱动
// =============================================================================
`ifndef SDCMD_TESTS_SV
`define SDCMD_TESTS_SV

// -----------------------------------------------------------------------------
// 基础 Test
// -----------------------------------------------------------------------------
class sdcmd_base_test extends uvm_test;
    `uvm_component_utils(sdcmd_base_test)

    sdcmd_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = sdcmd_env::type_id::create("env", this);
        // TODO: 配置 SD 卡模型并通过 config_db 传给 TB top
        // 例: uvm_config_db #(sd_card_cfg)::set(this, "*.card_model", "cfg", card_cfg)
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_test_body(phase);
        // Allow monitor time to observe the last DUT output and publish
        // Use a longer delay (100us) to ensure all transactions complete
        #100000;
        phase.drop_objection(this);
    endtask

    // 子类重写此方法
    virtual task run_test_body(uvm_phase phase);
    endtask
endclass : sdcmd_base_test

// -----------------------------------------------------------------------------
// Smoke Test: CMD8 + R7
// -----------------------------------------------------------------------------
class sdcmd_smoke_test extends sdcmd_base_test;
    `uvm_component_utils(sdcmd_smoke_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        sdcmd_single_seq seq;
        seq            = sdcmd_single_seq::type_id::create("seq");
        seq.cmd_val    = 6'd8;
        seq.arg_val    = 32'h0000_01AA;
        seq.clkdiv_val = 16'd4;
        seq.precnt_val = 16'd46;  
        seq.exp_timeout = 0;
        seq.start(env.agent.seqr);
        `uvm_info("TEST", "sdcmd_smoke_test: CMD8 sent, checking R7 response", UVM_NONE)
    endtask
endclass : sdcmd_smoke_test

// -----------------------------------------------------------------------------
// Init Test: 完整初始化序列
// -----------------------------------------------------------------------------
class sdcmd_init_test extends sdcmd_base_test;
    `uvm_component_utils(sdcmd_init_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        sdcmd_init_seq seq;
        seq = sdcmd_init_seq::type_id::create("seq");
        seq.acmd41_busy_rounds = 2;  // 模拟 2 次 busy 后才就绪
        seq.start(env.agent.seqr);
        `uvm_info("TEST", "sdcmd_init_test: Full init sequence completed", UVM_NONE)
    endtask
endclass : sdcmd_init_test

// -----------------------------------------------------------------------------
// Timeout Test
// -----------------------------------------------------------------------------
class sdcmd_timeout_test extends sdcmd_base_test;
    `uvm_component_utils(sdcmd_timeout_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // TODO: 通过 config_db 配置 sd_card_model 不响应
        // uvm_config_db #(bit)::set(this, "*.card_model", "inject_timeout", 1)
    endfunction

    virtual task run_test_body(uvm_phase phase);
        sdcmd_single_seq seq;
        seq = sdcmd_single_seq::type_id::create("seq");
        seq.cmd_val     = 6'd8;
        seq.arg_val     = 32'h0000_01AA;
        seq.exp_timeout = 1;
        seq.start(env.agent.seqr);
        `uvm_info("TEST", "sdcmd_timeout_test: timeout path verified", UVM_NONE)
    endtask
endclass : sdcmd_timeout_test

// -----------------------------------------------------------------------------
// CRC Error Test
// -----------------------------------------------------------------------------
class sdcmd_crc_error_test extends sdcmd_base_test;
    `uvm_component_utils(sdcmd_crc_error_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // TODO: 配置 sd_card_model 注入 CRC 错误
        // uvm_config_db #(bit)::set(this, "*.card_model", "inject_crc_error", 1)
    endfunction

    virtual task run_test_body(uvm_phase phase);
        sdcmd_error_seq seq;
        seq = sdcmd_error_seq::type_id::create("seq");
        seq.start(env.agent.seqr);
        `uvm_info("TEST", "sdcmd_crc_error_test: syntaxe path verified", UVM_NONE)
    endtask
endclass : sdcmd_crc_error_test

// -----------------------------------------------------------------------------
// R2 (136-bit) Test: CMD2 响应
// -----------------------------------------------------------------------------
class sdcmd_r2_test extends sdcmd_base_test;
    `uvm_component_utils(sdcmd_r2_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        sdcmd_single_seq seq;
        seq = sdcmd_single_seq::type_id::create("seq");
        seq.cmd_val    = 6'd2;     // ALL_SEND_CID
        seq.arg_val    = 32'h0;
        seq.exp_timeout = 0;
        seq.start(env.agent.seqr);
        `uvm_info("TEST", "sdcmd_r2_test: CMD2 R2 (136-bit) completed", UVM_NONE)
    endtask
endclass : sdcmd_r2_test

// -----------------------------------------------------------------------------
// Random Test: N 条随机命令 + 覆盖率驱动
// -----------------------------------------------------------------------------
class sdcmd_rand_test extends sdcmd_base_test;
    `uvm_component_utils(sdcmd_rand_test)

    int unsigned num_txns = 50;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        sdcmd_rand_seq seq;
        seq           = sdcmd_rand_seq::type_id::create("seq");
        seq.num_txns  = num_txns;
        seq.start(env.agent.seqr);
        `uvm_info("TEST", $sformatf("sdcmd_rand_test: %0d random txns completed", num_txns), UVM_NONE)
    endtask
endclass : sdcmd_rand_test

`endif // SDCMD_TESTS_SV
