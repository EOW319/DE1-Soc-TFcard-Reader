// =============================================================================
// sd_reader_sequences.sv
// Layer 2 — sd_reader 序列库
//
// 序列列表:
//   sd_reader_wait_init_seq    — 等待初始化完成 (不发 rstart)
//   sd_reader_single_read_seq  — 读单个扇区
//   sd_reader_multi_read_seq   — 连续读多个扇区
// =============================================================================
`ifndef SD_READER_SEQUENCES_SV
`define SD_READER_SEQUENCES_SV

// -----------------------------------------------------------------------------
// 等待初始化完成序列 (不驱动 rstart, 仅等待 rbusy=0)
// -----------------------------------------------------------------------------
class sd_reader_wait_init_seq extends uvm_sequence #(sd_reader_txn);
    `uvm_object_utils(sd_reader_wait_init_seq)

    function new(string name = "sd_reader_wait_init_seq");
        super.new(name);
    endfunction

    task body();
        sd_reader_txn txn;
        // 发一个 wait_init=1 的特殊 txn，sector 为 0 (driver 会等待 rbusy=0 后返回)
        txn = sd_reader_txn::type_id::create("txn_init");
        start_item(txn);
        txn.sector     = 32'h0;
        txn.wait_init  = 1'b1;
        finish_item(txn);
        `uvm_info("SEQ", "SD reader initialization complete (rbusy=0)", UVM_MEDIUM)
    endtask
endclass : sd_reader_wait_init_seq

// -----------------------------------------------------------------------------
// 单扇区读取序列
// -----------------------------------------------------------------------------
class sd_reader_single_read_seq extends uvm_sequence #(sd_reader_txn);
    `uvm_object_utils(sd_reader_single_read_seq)

    bit [31:0] target_sector = 32'h0;

    function new(string name = "sd_reader_single_read_seq");
        super.new(name);
    endfunction

    task body();
        sd_reader_txn txn;
        txn = sd_reader_txn::type_id::create("txn_read");
        start_item(txn);
        txn.sector    = target_sector;
        txn.wait_init = 1'b0;
        finish_item(txn);
        `uvm_info("SEQ", $sformatf("Single read sector=0x%08X done", target_sector), UVM_MEDIUM)
    endtask
endclass : sd_reader_single_read_seq

// -----------------------------------------------------------------------------
// 多扇区连续读取序列
// -----------------------------------------------------------------------------
class sd_reader_multi_read_seq extends uvm_sequence #(sd_reader_txn);
    `uvm_object_utils(sd_reader_multi_read_seq)

    int unsigned       num_sectors = 4;
    rand bit [31:0]    start_sector;

    constraint c_start { start_sector inside {[32'h1 : 32'h0000_FFF0]}; }

    function new(string name = "sd_reader_multi_read_seq");
        super.new(name);
    endfunction

    task body();
        sd_reader_txn txn;
        for (int i = 0; i < num_sectors; i++) begin
            txn = sd_reader_txn::type_id::create($sformatf("txn_read_%0d", i));
            start_item(txn);
            txn.sector    = start_sector + i;
            txn.wait_init = 1'b0;
            finish_item(txn);
            `uvm_info("SEQ", $sformatf("Multi read [%0d]: sector=0x%08X", i, txn.sector), UVM_HIGH)
        end
    endtask
endclass : sd_reader_multi_read_seq

`endif // SD_READER_SEQUENCES_SV
