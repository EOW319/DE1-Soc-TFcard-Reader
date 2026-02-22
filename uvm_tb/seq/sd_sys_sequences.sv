// =============================================================================
// sd_sys_sequences.sv
// Layer 3 — 全系统序列库
//
// sys_normal_seq         — 正常流程 (等待文件读取完成 + VGA 输出稳定)
// sys_no_file_seq        — 卡内无 IMAGE.BIN 文件
// =============================================================================
`ifndef SD_SYS_SEQUENCES_SV
`define SD_SYS_SEQUENCES_SV

// 系统级 txn (控制卡模型配置，无需实际驱动 DUT 输入)
class sd_sys_txn extends uvm_sequence_item;
    bit        has_image_file      = 1;    // 卡内是否存在 IMAGE.BIN
    bit [7:0]  sectors_per_cluster = 8'd8; // FAT32 BPB 参数
    bit [31:0] partition_start_lba = 32'h800;
    bit [15:0] reserved_sectors    = 16'd32;

    `uvm_object_utils_begin(sd_sys_txn)
        `uvm_field_int(has_image_file,       UVM_ALL_ON)
        `uvm_field_int(sectors_per_cluster,  UVM_ALL_ON)
        `uvm_field_int(partition_start_lba,  UVM_ALL_ON)
        `uvm_field_int(reserved_sectors,     UVM_ALL_ON)
    `uvm_object_utils_end
    
    function new(string name = "sd_sys_txn");
        super.new(name);
    endfunction
endclass : sd_sys_txn

// 正常流程序列: 等待 read_done 信号
class sys_normal_seq extends uvm_sequence #(sd_sys_txn);
    `uvm_object_utils(sys_normal_seq)

    // 超时周期 (仿真时): SIMULATE=1 模式下初始化约几千周期
    int unsigned timeout_cycles = 100_000;

    function new(string name = "sys_normal_seq");
        super.new(name);
    endfunction

    task body();
        sd_sys_txn txn;
        txn = sd_sys_txn::type_id::create("txn_normal");
        start_item(txn);
        txn.has_image_file = 1;
        finish_item(txn);
        `uvm_info("SEQ", "sys_normal_seq: waiting for read_done...", UVM_MEDIUM)
        // 等待逻辑在 test 中实现
    endtask
endclass : sys_normal_seq

// 无文件序列
class sys_no_file_seq extends uvm_sequence #(sd_sys_txn);
    `uvm_object_utils(sys_no_file_seq)

    function new(string name = "sys_no_file_seq");
        super.new(name);
    endfunction

    task body();
        sd_sys_txn txn;
        txn = sd_sys_txn::type_id::create("txn_nofile");
        start_item(txn);
        txn.has_image_file = 0;  // 不写 IMAGE.BIN 目录项到卡模型
        finish_item(txn);
        `uvm_info("SEQ", "sys_no_file_seq: IMAGE.BIN absent, expecting ERROR state", UVM_MEDIUM)
    endtask
endclass : sys_no_file_seq

`endif // SD_SYS_SEQUENCES_SV
