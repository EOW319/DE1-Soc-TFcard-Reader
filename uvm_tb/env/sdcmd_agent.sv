// =============================================================================
// sdcmd_agent.sv
// Layer 1 — sdcmd_ctrl Host Agent
// 包含: sdcmd_host_driver + sdcmd_host_monitor + sdcmd_host_agent
//
// Agent 拓扑:
//   sdcmd_host_agent
//   ├── sdcmd_host_driver   — 驱动 DUT 输入 (start/cmd/arg/clkdiv/precnt)
//   └── sdcmd_host_monitor  — 采样 CMD 线 48-bit 帧 + DUT 输出状态
// =============================================================================
`ifndef SDCMD_AGENT_SV
`define SDCMD_AGENT_SV

// -----------------------------------------------------------------------------
// Transaction: sdcmd_txn
// -----------------------------------------------------------------------------
class sdcmd_txn extends uvm_sequence_item;
    // 随机化字段
    rand bit [5:0]  cmd;
    rand bit [31:0] arg;
    rand bit [15:0] clkdiv;
    rand bit [15:0] precnt;

    // 定向测试控制字段 (非随机)
    bit expect_timeout;
    bit expect_crc_err;
        `uvm_object_utils_begin(sdcmd_txn)
        `uvm_field_int(cmd,             UVM_ALL_ON)
        `uvm_field_int(arg,             UVM_ALL_ON)
        `uvm_field_int(clkdiv,          UVM_ALL_ON)
        `uvm_field_int(precnt,          UVM_ALL_ON)
        `uvm_field_int(expect_timeout,  UVM_ALL_ON)
        `uvm_field_int(expect_crc_err,  UVM_ALL_ON)
    `uvm_object_utils_end
    // 约束
    constraint c_cmd    { cmd    inside {6'd0, 6'd2, 6'd3, 6'd7, 6'd8, 6'd16, 6'd17, 6'd41, 6'd55}; }
    constraint c_clkdiv { clkdiv inside {[1:200]}; }
    constraint c_precnt { precnt inside {[46:500]}; }

    function new(string name = "sdcmd_txn");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("CMD%0d arg=0x%08X clkdiv=%0d precnt=%0d exp_to=%0b exp_crc=%0b",
                         cmd, arg, clkdiv, precnt, expect_timeout, expect_crc_err);
    endfunction
endclass : sdcmd_txn

// -----------------------------------------------------------------------------
// Monitor Item: sdcmd_mon_item
// 由 Monitor 发布到 analysis port 的数据包
// -----------------------------------------------------------------------------
class sdcmd_mon_item extends uvm_sequence_item;
    bit [47:0] cmd_frame;    // 捕获到的 host 命令帧 (48-bit)
    bit [47:0] resp_frame;   // 捕获到的响应帧 (48-bit，R2 使用 resp_frame_r2)
    bit [135:0] resp_frame_r2; // R2 长响应 (136-bit)
    bit        resp_valid;   // 收到响应
    bit        got_done;
    bit        got_timeout;
    bit        got_syntaxe;
    bit [31:0] resparg;      // DUT 输出的 resparg
    bit [5:0]  dut_resp_cmd_idx_dbg; // DUT 内部 resp_reg[45:40]
    bit [15:0] clkdiv;       // 采样的 clkdiv (供 coverage 使用)
    bit [15:0] precnt;       // 采样的 precnt (供 coverage 使用)

    `uvm_object_utils_begin(sdcmd_mon_item)
        `uvm_field_int(cmd_frame,   UVM_ALL_ON)
        `uvm_field_int(resp_frame,  UVM_ALL_ON)
        `uvm_field_int(resp_valid,  UVM_ALL_ON)
        `uvm_field_int(got_done,    UVM_ALL_ON)
        `uvm_field_int(got_timeout, UVM_ALL_ON)
        `uvm_field_int(got_syntaxe, UVM_ALL_ON)
        `uvm_field_int(resparg,     UVM_ALL_ON)
        `uvm_field_int(dut_resp_cmd_idx_dbg, UVM_ALL_ON)
        `uvm_field_int(clkdiv,      UVM_ALL_ON)
        `uvm_field_int(precnt,      UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "sdcmd_mon_item");
        super.new(name);
    endfunction
endclass : sdcmd_mon_item

// -----------------------------------------------------------------------------
// Driver: sdcmd_host_driver
// -----------------------------------------------------------------------------
class sdcmd_host_driver extends uvm_driver #(sdcmd_txn);
    `uvm_component_utils(sdcmd_host_driver)

    virtual sdcmd_if.host_drv vif;

    uvm_analysis_port #(sdcmd_txn) txn_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual sdcmd_if.host_drv)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", {"Cannot get sdcmd_if.host_drv for ", get_full_name()})
        txn_ap = new("txn_ap", this);
    endfunction

    task run_phase(uvm_phase phase);
        sdcmd_txn txn;
        // 等待复位释放
        @(posedge vif.rstn);
        @(posedge vif.clk);

        forever begin
            seq_item_port.get_next_item(txn);
            drive_txn(txn);
            seq_item_port.item_done();
        end
    endtask

    // 驱动单条 transaction 到 DUT
    task automatic drive_txn(sdcmd_txn txn);
        // 等待 DUT 不忙
        while (vif.busy) @(posedge vif.clk);

        // 建立输入信号
        vif.clkdiv <= txn.clkdiv;
        vif.precnt <= txn.precnt;
        vif.cmd    <= txn.cmd;
        vif.arg    <= txn.arg;
        vif.start  <= 1'b0;
        @(posedge vif.clk);

        // 发出 start 脉冲 (1 个时钟)
        vif.start <= 1'b1;
        @(posedge vif.clk);
        vif.start <= 1'b0;

        // 等待 done / timeout / syntaxe (clock-synchronous polling)
        do @(posedge vif.clk); while (!(vif.done || vif.timeout || vif.syntaxe));
        txn_ap.write(txn);
    endtask
endclass : sdcmd_host_driver

// -----------------------------------------------------------------------------
// Monitor: sdcmd_host_monitor
// 在 sdclk 上升沿捕获 CMD 线上的帧，独立于 DUT 内部信号
// -----------------------------------------------------------------------------
class sdcmd_host_monitor extends uvm_monitor;
    `uvm_component_utils(sdcmd_host_monitor)

    virtual sdcmd_if.host_mon vif;
    uvm_analysis_port #(sdcmd_mon_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual sdcmd_if.host_mon)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", {"Cannot get sdcmd_if.host_mon for ", get_full_name()})
    endfunction

    task run_phase(uvm_phase phase);
        sdcmd_mon_item item;
        `uvm_info("MON", "sdcmd_host_monitor run_phase started", UVM_MEDIUM)
        // Wait for reset release
        @(posedge vif.rstn);
        `uvm_info("MON", "Reset released, waiting for start pulse", UVM_MEDIUM)
        forever begin
            // ---- Wait for DUT to accept a command (start pulse) ----
            // Use clock-synchronous polling instead of @(posedge vif.start)
            // to avoid edge-detection issues on virtual interface modports
            do @(posedge vif.clk); while (!vif.start);
            `uvm_info("MON", "Start pulse detected", UVM_MEDIUM)
            // Wait for start to go low and then one more clock to stabilize signals
            do @(posedge vif.clk); while (vif.start);
            @(posedge vif.clk);

            item = sdcmd_mon_item::type_id::create("item");
            // Snapshot the DUT input signals driven by the driver
            // Now cmd/arg should be stable after start pulse
            item.clkdiv = vif.clkdiv;
            item.precnt = vif.precnt;
            // Reconstruct cmd_frame from DUT inputs
            item.cmd_frame = {1'b0, 1'b1, vif.cmd, vif.arg, 7'h0, 1'b1};

            // ---- Wait for transaction to complete ----
            // Poll for done/timeout/syntaxe on clock edges
            do @(posedge vif.clk); while (!(vif.done || vif.timeout || vif.syntaxe));
            `uvm_info("MON", "Transaction completed", UVM_MEDIUM)
            // Extra clock delay to ensure driver publishes txn to FIFO first
            @(posedge vif.clk);
            item.got_done    = vif.done;
            item.got_timeout = vif.timeout;
            item.got_syntaxe = vif.syntaxe;
            item.resparg     = vif.resparg;
            item.dut_resp_cmd_idx_dbg = vif.dut_resp_cmd_idx_dbg;
            item.resp_valid  = vif.done;

            `uvm_info("MON", $sformatf("Observed CMD%0d arg=0x%08X done=%0b to=%0b syn=%0b resparg=0x%08X",
                      item.cmd_frame[45:40], item.cmd_frame[39:8],
                      item.got_done, item.got_timeout, item.got_syntaxe, item.resparg), UVM_MEDIUM)
            ap.write(item);
        end
    endtask
endclass : sdcmd_host_monitor

// -----------------------------------------------------------------------------
// Agent: sdcmd_host_agent
// -----------------------------------------------------------------------------
class sdcmd_host_agent extends uvm_agent;
    `uvm_component_utils(sdcmd_host_agent)

    sdcmd_host_driver  drv;
    sdcmd_host_monitor mon;
    uvm_sequencer #(sdcmd_txn) seqr;

    // analysis port 透传 (连接 env 中的 scoreboard 和 coverage)
    uvm_analysis_port #(sdcmd_mon_item) ap;
    uvm_analysis_port #(sdcmd_txn) txn_ap;
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap   = new("ap", this);
        txn_ap = new("txn_ap", this);
        seqr = uvm_sequencer #(sdcmd_txn)::type_id::create("seqr", this);
        if (is_active == UVM_ACTIVE) begin
            drv = sdcmd_host_driver::type_id::create("drv", this);
        end
        mon = sdcmd_host_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        if (is_active == UVM_ACTIVE) begin
            drv.seq_item_port.connect(seqr.seq_item_export);
            drv.txn_ap.connect(txn_ap);
        end
        mon.ap.connect(ap);
    endfunction
endclass : sdcmd_host_agent

`endif // SDCMD_AGENT_SV
