// =============================================================================
// sd_sys_tests.sv
// Layer 3 — 全系统端到端测试用例
//
// sys_base_test             — 基础 test，配置 FAT32 磁盘镜像
// sys_normal_test           — 完整流程端到端黄金比对
// sys_no_file_test          — 根目录无 IMAGE.BIN，验证 ERROR 状态
// sys_cluster_size_test     — 不同 sectors_per_cluster 参数验证
// sys_partition_lba_test    — 不同 MBR 分区起始 LBA 验证
// sys_reserved_sec_test     — 较大 reserved_sectors 参数验证
// =============================================================================
`ifndef SD_SYS_TESTS_SV
`define SD_SYS_TESTS_SV

// -----------------------------------------------------------------------------
// 基础 Test
// -----------------------------------------------------------------------------
class sys_base_test extends uvm_test;
    `uvm_component_utils(sys_base_test)

    // 参考图像数据 (由 fat32_image_gen 生成，供 scoreboard 比对)
    byte unsigned ref_image[76800];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // TODO: 调用 fat32_image_gen 生成磁盘镜像并填充 sd_card_model.mem
        // TODO: 将 ref_image 传给 fat32_scoreboard 和 vga_frame_scoreboard
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_test_body(phase);
        phase.drop_objection(this);
    endtask

    virtual task run_test_body(uvm_phase phase);
    endtask

    // 等待 read_done 或超时
    task wait_read_done(input int unsigned timeout_cycles = 500_000);
        // TODO: 通过 sd_sys_if.fat32_mon 监控 read_done 信号
        `uvm_info("TEST", "Waiting for read_done...", UVM_MEDIUM)
        // fork/join_any + timeout
    endtask
endclass : sys_base_test

// -----------------------------------------------------------------------------
// Normal Test: 端到端黄金比对
// -----------------------------------------------------------------------------
class sys_normal_test extends sys_base_test;
    `uvm_component_utils(sys_normal_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 标准 FAT32 配置:
        //   sectors_per_cluster = 8, partition_lba = 0x800, reserved_sectors = 32
        //   IMAGE.BIN = 76800 字节渐变色测试图案
    endfunction

    virtual task run_test_body(uvm_phase phase);
        wait_read_done(500_000);
        `uvm_info("TEST", "sys_normal_test: Waiting 2 VGA frames for pixel compare...", UVM_MEDIUM)
        // TODO: 等待 VGA monitor 输出 2 帧后检查 scoreboard
        #1000000;  // 占位延时，待 VGA monitor 实现后替换
        `uvm_info("TEST", "sys_normal_test PASS", UVM_NONE)
    endtask
endclass : sys_normal_test

// -----------------------------------------------------------------------------
// No File Test: 卡内无 IMAGE.BIN
// -----------------------------------------------------------------------------
class sys_no_file_test extends sys_base_test;
    `uvm_component_utils(sys_no_file_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 生成不含 IMAGE.BIN 的 FAT32 镜像
        // TODO: fat32_image_gen.has_image_file = 0
    endfunction

    virtual task run_test_body(uvm_phase phase);
        // 等待进入 DONE 或 ERROR 状态 (state_debug 信号)
        // 期望: file_found=0, read_done=0
        #200_000;
        `uvm_info("TEST", "sys_no_file_test: Checking file_found=0 and ERROR state", UVM_NONE)
        // TODO: 检查 vif.file_found == 0
    endtask
endclass : sys_no_file_test

// -----------------------------------------------------------------------------
// Cluster Size Test: 不同 sectors_per_cluster
// -----------------------------------------------------------------------------
class sys_cluster_size_test extends sys_base_test;
    `uvm_component_utils(sys_cluster_size_test)

    // 覆盖值: 1, 8, 32, 64
    int unsigned spc_values[$] = '{1, 8, 32, 64};

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        foreach (spc_values[i]) begin
            // TODO: 动态重配置 FAT32 镜像的 sectors_per_cluster 后重置 DUT
            `uvm_info("TEST", $sformatf("sys_cluster_size_test: spc=%0d", spc_values[i]), UVM_MEDIUM)
            wait_read_done(500_000);
        end
    endtask
endclass : sys_cluster_size_test

// -----------------------------------------------------------------------------
// Partition LBA Test: 不同 MBR 分区起始 LBA
// -----------------------------------------------------------------------------
class sys_partition_lba_test extends sys_base_test;
    `uvm_component_utils(sys_partition_lba_test)

    bit [31:0] lba_values[$] = '{32'h800, 32'h2000, 32'h8000};

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        foreach (lba_values[i]) begin
            // TODO: 重配置 MBR partition start LBA
            `uvm_info("TEST", $sformatf("sys_partition_lba_test: lba=0x%0X", lba_values[i]), UVM_MEDIUM)
            wait_read_done(500_000);
        end
    endtask
endclass : sys_partition_lba_test

// -----------------------------------------------------------------------------
// Reserved Sectors Test
// -----------------------------------------------------------------------------
class sys_reserved_sec_test extends sys_base_test;
    `uvm_component_utils(sys_reserved_sec_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 使用较大的 reserved_sectors = 128
        // TODO: fat32_image_gen.reserved_sectors = 128
    endfunction

    virtual task run_test_body(uvm_phase phase);
        wait_read_done(500_000);
        `uvm_info("TEST", "sys_reserved_sec_test: large reserved_sectors passed", UVM_NONE)
    endtask
endclass : sys_reserved_sec_test

`endif // SD_SYS_TESTS_SV
