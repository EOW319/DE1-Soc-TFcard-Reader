// =============================================================================
// sd_reader_agent.sv
// Layer 2 — sd_reader Host Agent
// 包含: sd_reader_txn / sd_reader_host_driver / sd_reader_host_monitor
//             / sd_reader_host_agent
//
// Driver 驱动: rstart / rsector
// Monitor 监控: rbusy / rdone / outen / outbyte (512B 数据流收集)
// =============================================================================
`ifndef SD_READER_AGENT_SV
`define SD_READER_AGENT_SV

// -----------------------------------------------------------------------------
// Transaction: sd_reader_txn
// -----------------------------------------------------------------------------
class sd_reader_txn extends uvm_sequence_item;
    `uvm_object_utils_begin(sd_reader_txn)
        `uvm_field_int(sector,     UVM_ALL_ON)
        `uvm_field_int(wait_init,  UVM_ALL_ON)
    `uvm_object_utils_end

    rand bit [31:0] sector;      // 目标扇区地址
    bit             wait_init;   // 若为 1，等待 rbusy=0 后再发 rstart (初始化完成)

    constraint c_sector { sector inside {[32'h0 : 32'h0000_FFFF]}; }  // 调整范围按需

    function new(string name = "sd_reader_txn");
        super.new(name);
    endfunction
endclass : sd_reader_txn

// -----------------------------------------------------------------------------
// Monitor Item: sd_reader_mon_item
// 一次扇区读取的完整结果
// -----------------------------------------------------------------------------
class sd_reader_mon_item extends uvm_sequence_item;
    `uvm_object_utils_begin(sd_reader_mon_item)
        `uvm_field_int(sector,       UVM_ALL_ON)
        `uvm_field_sarray_int(data,  UVM_ALL_ON)
        `uvm_field_int(byte_count,   UVM_ALL_ON)
        `uvm_field_int(got_rdone,    UVM_ALL_ON)
    `uvm_object_utils_end

    bit [31:0] sector;
    byte       data[512];    // 512 字节扇区数据
    int        byte_count;   // 实际接收字节数
    bit        got_rdone;

    function new(string name = "sd_reader_mon_item");
        super.new(name);
    endfunction
endclass : sd_reader_mon_item

// -----------------------------------------------------------------------------
// Driver: sd_reader_host_driver
// -----------------------------------------------------------------------------
class sd_reader_host_driver extends uvm_driver #(sd_reader_txn);
    `uvm_component_utils(sd_reader_host_driver)

    virtual sd_reader_if.host_drv vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual sd_reader_if.host_drv)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", {"Cannot get sd_reader_if.host_drv for ", get_full_name()})
    endfunction

    task run_phase(uvm_phase phase);
        sd_reader_txn txn;
        @(posedge vif.rst_n);
        @(posedge vif.clk);
        forever begin
            seq_item_port.get_next_item(txn);
            drive_txn(txn);
            seq_item_port.item_done();
        end
    endtask

    task automatic drive_txn(sd_reader_txn txn);
        // 若 wait_init=1，等待初始化完成 (rbusy=0)
        if (txn.wait_init) begin
            wait (!vif.rbusy);
            @(posedge vif.clk);
        end
        // 等待 rbusy=0 (上一次读取完成)
        while (vif.rbusy) @(posedge vif.clk);

        vif.rsector <= txn.sector;
        vif.rstart  <= 1'b1;
        @(posedge vif.clk);
        vif.rstart  <= 1'b0;

        // 等待 rdone
        wait (vif.rdone);
        @(posedge vif.clk);
    endtask
endclass : sd_reader_host_driver

// -----------------------------------------------------------------------------
// Monitor: sd_reader_host_monitor
// 收集 outen/outbyte 输出流，每 512 字节打包成一个 mon_item
// -----------------------------------------------------------------------------
class sd_reader_host_monitor extends uvm_monitor;
    `uvm_component_utils(sd_reader_host_monitor)

    virtual sd_reader_if.host_mon vif;
    uvm_analysis_port #(sd_reader_mon_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual sd_reader_if.host_mon)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", {"Cannot get sd_reader_if.host_mon for ", get_full_name()})
    endfunction

    task run_phase(uvm_phase phase);
        // TODO: 实现字节流收集
        // 步骤:
        //   1. 等待 rstart 上升沿，记录 rsector
        //   2. 在每个 outen 脉冲上采样 outbyte，填入 data[]
        //   3. 收集 512 字节后等待 rdone
        //   4. 构建 sd_reader_mon_item 并 ap.write()
        `uvm_info("MON", "sd_reader_host_monitor run_phase started (TODO: implement byte stream capture)", UVM_MEDIUM)
        forever @(posedge vif.clk);
    endtask
endclass : sd_reader_host_monitor

// -----------------------------------------------------------------------------
// Agent: sd_reader_host_agent
// -----------------------------------------------------------------------------
class sd_reader_host_agent extends uvm_agent;
    `uvm_component_utils(sd_reader_host_agent)

    sd_reader_host_driver  drv;
    sd_reader_host_monitor mon;
    uvm_sequencer #(sd_reader_txn) seqr;
    uvm_analysis_port #(sd_reader_mon_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap   = new("ap", this);
        seqr = uvm_sequencer #(sd_reader_txn)::type_id::create("seqr", this);
        if (is_active == UVM_ACTIVE)
            drv = sd_reader_host_driver::type_id::create("drv", this);
        mon = sd_reader_host_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        if (is_active == UVM_ACTIVE)
            drv.seq_item_port.connect(seqr.seq_item_export);
        mon.ap.connect(ap);
    endfunction
endclass : sd_reader_host_agent

`endif // SD_READER_AGENT_SV
