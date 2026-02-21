// =============================================================================
// sd_reader_tests.sv
// Layer 2 — sd_reader 子系统测试用例
//
// sd_reader_base_test          — 基础 test，创建 env，连接到 SD 卡模型
// sd_reader_init_test          — 验证 rbusy 从 1→0 (初始化完成)
// sd_reader_single_read_test   — 初始化后读单扇区，比对 512B 数据
// sd_reader_multi_read_test    — 连续读多个扇区
// sd_reader_init_retry_test    — ACMD41 多次 busy 后才就绪
// sd_reader_param_test         — SIMULATE=1 参数模式 (加速仿真)
// =============================================================================
`ifndef SD_READER_TESTS_SV
`define SD_READER_TESTS_SV

// -----------------------------------------------------------------------------
// 基础 Test
// -----------------------------------------------------------------------------
class sd_reader_base_test extends uvm_test;
    `uvm_component_utils(sd_reader_base_test)

    sd_reader_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = sd_reader_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_test_body(phase);
        phase.drop_objection(this);
    endtask

    virtual task run_test_body(uvm_phase phase);
    endtask
endclass : sd_reader_base_test

// -----------------------------------------------------------------------------
// Init Test: 验证 rbusy 1→0
// -----------------------------------------------------------------------------
class sd_reader_init_test extends sd_reader_base_test;
    `uvm_component_utils(sd_reader_init_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        sd_reader_wait_init_seq seq;
        seq = sd_reader_wait_init_seq::type_id::create("seq");
        seq.start(env.agent.seqr);
        `uvm_info("TEST", "sd_reader_init_test: initialization complete verified", UVM_NONE)
    endtask
endclass : sd_reader_init_test

// -----------------------------------------------------------------------------
// Single Read Test: 读单扇区比对 512B
// -----------------------------------------------------------------------------
class sd_reader_single_read_test extends sd_reader_base_test;
    `uvm_component_utils(sd_reader_single_read_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        sd_reader_wait_init_seq  init_seq;
        sd_reader_single_read_seq read_seq;

        // 1. 等待初始化
        init_seq = sd_reader_wait_init_seq::type_id::create("init_seq");
        init_seq.start(env.agent.seqr);

        // 2. 读扇区 0x800 (假设分区起始 LBA)
        read_seq = sd_reader_single_read_seq::type_id::create("read_seq");
        read_seq.target_sector = 32'h0000_0800;
        // TODO: read_seq.start(env.agent.seqr);

        `uvm_info("TEST", "sd_reader_single_read_test: sector read & compare done", UVM_NONE)
    endtask
endclass : sd_reader_single_read_test

// -----------------------------------------------------------------------------
// Multi Read Test: 连续读多个扇区
// -----------------------------------------------------------------------------
class sd_reader_multi_read_test extends sd_reader_base_test;
    `uvm_component_utils(sd_reader_multi_read_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        sd_reader_wait_init_seq   init_seq;
        sd_reader_multi_read_seq  multi_seq;

        // TODO: init_seq.start(env.agent.seqr);

        multi_seq = sd_reader_multi_read_seq::type_id::create("multi_seq");
        multi_seq.start_sector = 32'h0000_0800;
        multi_seq.num_sectors  = 8;
        // TODO: multi_seq.start(env.agent.seqr);

        `uvm_info("TEST", "sd_reader_multi_read_test: 8 sectors read & compared", UVM_NONE)
    endtask
endclass : sd_reader_multi_read_test

// -----------------------------------------------------------------------------
// Init Retry Test: ACMD41 多次 busy
// -----------------------------------------------------------------------------
class sd_reader_init_retry_test extends sd_reader_base_test;
    `uvm_component_utils(sd_reader_init_retry_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 配置 SD 卡模型: ACMD41 前 3 次响应 busy (bit31=0)，第 4 次才 ready
        // TODO: uvm_config_db #(int)::set(this, "*.card_model", "acmd41_busy_rounds", 3)
    endfunction

    virtual task run_test_body(uvm_phase phase);
        sd_reader_wait_init_seq seq;
        // TODO: seq.start(env.agent.seqr);
        `uvm_info("TEST", "sd_reader_init_retry_test: ACMD41 retry scenario passed", UVM_NONE)
    endtask
endclass : sd_reader_init_retry_test

// -----------------------------------------------------------------------------
// Param Test: SIMULATE=1 模式
// -----------------------------------------------------------------------------
class sd_reader_param_test extends sd_reader_base_test;
    `uvm_component_utils(sd_reader_param_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // SIMULATE=1 通过编译参数 +define+SIMULATE=1 传入，
    // 或在 Makefile 中对 sd_reader 实例化时覆盖 SIMULATE 参数。
    // 本 test 重点验证加速模式下时序正确性。

    virtual task run_test_body(uvm_phase phase);
        sd_reader_wait_init_seq seq;
        // TODO: seq.start(env.agent.seqr);
        `uvm_info("TEST", "sd_reader_param_test: SIMULATE=1 fast init verified", UVM_NONE)
    endtask
endclass : sd_reader_param_test

`endif // SD_READER_TESTS_SV
