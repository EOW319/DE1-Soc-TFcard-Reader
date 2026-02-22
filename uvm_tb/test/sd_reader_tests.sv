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
        sd_reader_single_read_seq read_seq;

        read_seq = sd_reader_single_read_seq::type_id::create("read_seq");
        read_seq.target_sector = 32'h0000_0800;
        read_seq.start(env.agent.seqr);

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

        init_seq = sd_reader_wait_init_seq::type_id::create("init_seq");
        init_seq.start(env.agent.seqr);

        multi_seq = sd_reader_multi_read_seq::type_id::create("multi_seq");
        multi_seq.start_sector = 32'h0000_0800;
        multi_seq.num_sectors  = 8;
        multi_seq.start(env.agent.seqr);

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
        uvm_config_db #(int)::set(null, "uvm_test_top", "acmd41_busy_rounds", 3);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        sd_reader_wait_init_seq seq;
        sd_reader_single_read_seq read_seq;

        seq = sd_reader_wait_init_seq::type_id::create("seq");
        seq.start(env.agent.seqr);
        read_seq = sd_reader_single_read_seq::type_id::create("read_seq");
        read_seq.target_sector = 32'h0000_0800;
        read_seq.start(env.agent.seqr);
        `uvm_info("TEST", "sd_reader_init_retry_test: ACMD41 retry scenario passed", UVM_NONE)
    endtask
endclass : sd_reader_init_retry_test

// -----------------------------------------------------------------------------
// Random Error Stress Test:
// 随机注入响应 cmd/crc 错误，完成 20 次连续读
// -----------------------------------------------------------------------------
class sd_reader_rand_resp_error_20read_test extends sd_reader_base_test;
    `uvm_component_utils(sd_reader_rand_resp_error_20read_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        sd_reader_wait_init_seq   init_seq;
        sd_reader_single_read_seq read_seq;
        bit inj_cmd;
        bit inj_crc;
        int seed;
        int burst_len;
        int clean_len;

        seed = 32'h26022101;
        void'($urandom(seed));

        // 阶段1: 仅在初始化 busy 窗口注入（短脉冲 + 清洁窗口，避免饿死初始化）
        @(posedge env.agent.drv.vif.rst_n);
        while (env.agent.drv.vif.rbusy) begin
            // 清洁窗口: 让初始化状态机有机会前进
            clean_len = $urandom_range(32, 96);
            repeat (clean_len) begin
                @(posedge env.agent.drv.vif.clk);
                if (!env.agent.drv.vif.rbusy) break;
                void'(uvm_hdl_deposit("tb_sd_reader_top.u_card_model.inject_wrong_cmd", 1'b0));
                void'(uvm_hdl_deposit("tb_sd_reader_top.u_card_model.inject_crc_error", 1'b0));
            end

            if (!env.agent.drv.vif.rbusy) break;

            // 错误脉冲: 稀疏地注入，且每次保持若干拍，避免每拍抖动
            burst_len = $urandom_range(2, 8);
            inj_cmd   = ($urandom_range(0, 99) < 5);
            inj_crc   = ($urandom_range(0, 99) < 15);
            repeat (burst_len) begin
                @(posedge env.agent.drv.vif.clk);
                if (!env.agent.drv.vif.rbusy) break;
                void'(uvm_hdl_deposit("tb_sd_reader_top.u_card_model.inject_wrong_cmd", inj_cmd));
                void'(uvm_hdl_deposit("tb_sd_reader_top.u_card_model.inject_crc_error", inj_crc));
            end
        end

        // 一旦 rbusy 拉低，立即停止注入
        void'(uvm_hdl_deposit("tb_sd_reader_top.u_card_model.inject_wrong_cmd", 1'b0));
        void'(uvm_hdl_deposit("tb_sd_reader_top.u_card_model.inject_crc_error", 1'b0));

        init_seq = sd_reader_wait_init_seq::type_id::create("init_seq");
        init_seq.start(env.agent.seqr);

        // 阶段2: 连续读 20 个扇区（不再注入错误，保证事务可完成）
        for (int i = 0; i < 20; i++) begin
            inj_cmd = 1'b0;
            inj_crc = 1'b0;

            read_seq = sd_reader_single_read_seq::type_id::create($sformatf("read_seq_%0d", i));
            read_seq.target_sector = 32'h0000_0800 + i;

            `uvm_info("TEST", $sformatf(
                      "rand_resp_error[%0d]: sector=0x%08X inject_wrong_cmd=%0b inject_crc_error=%0b",
                      i, read_seq.target_sector, inj_cmd, inj_crc), UVM_MEDIUM)

            read_seq.start(env.agent.seqr);
        end

        `uvm_info("TEST", "sd_reader_rand_resp_error_20read_test: inject during init busy window, then 20 consecutive reads done", UVM_NONE)
    endtask
endclass : sd_reader_rand_resp_error_20read_test

// -----------------------------------------------------------------------------
// Param Test: SIMULATE=1 参数模式 (加速仿真)
// 验证 DUT 在 SIMULATE=1 模式下初始化并完成单扇区读取
// (tb_sd_reader_top 已经使用 SIMULATE=1，本 test 确认该路径可用)
// -----------------------------------------------------------------------------
class sd_reader_param_test extends sd_reader_base_test;
    `uvm_component_utils(sd_reader_param_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        sd_reader_wait_init_seq   init_seq;
        sd_reader_single_read_seq read_seq;

        // 验证 SIMULATE=1 路径: 初始化应快速完成
        init_seq = sd_reader_wait_init_seq::type_id::create("init_seq");
        init_seq.start(env.agent.seqr);
        `uvm_info("TEST", "sd_reader_param_test: SIMULATE=1 init complete", UVM_NONE)

        // 读一个扇区确认数据路径正常
        read_seq = sd_reader_single_read_seq::type_id::create("read_seq");
        read_seq.target_sector = 32'h0000_0800;
        read_seq.start(env.agent.seqr);
        `uvm_info("TEST", "sd_reader_param_test: SIMULATE=1 single read verified", UVM_NONE)
    endtask
endclass : sd_reader_param_test


`endif // SD_READER_TESTS_SV
