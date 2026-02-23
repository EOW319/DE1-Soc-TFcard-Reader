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
//
// 注意: fat32_image_gen 使用 package 级编译期参数。
//       对于 cluster_size / partition_lba / reserved_sectors 等变参测试，
//       需要重新编译或通过 TB top 的 plusarg 控制镜像生成。
//       当前默认配置: spc=8, partition_lba=0x800, reserved=32, has_file=1
// =============================================================================
`ifndef SD_SYS_TESTS_SV
`define SD_SYS_TESTS_SV

// -----------------------------------------------------------------------------
// 基础 Test
// -----------------------------------------------------------------------------
class sys_base_test extends uvm_test;
    `uvm_component_utils(sys_base_test)

    sd_sys_env env;

    // 虚接口 (用于 wait_read_done 等待信号)
    virtual sd_sys_if.fat32_mon vif_fat32;

    // 参考图像数据 (与 fat32_image_gen::write_file_data 同公式生成)
    byte unsigned ref_image[76800];

    // 控制是否跳过 scoreboard 比对 (no_file_test 用)
    bit skip_ram_compare = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // 创建 env
        env = sd_sys_env::type_id::create("env", this);

        // 获取 vif 用于 wait_read_done
        if (!uvm_config_db#(virtual sd_sys_if.fat32_mon)::get(this, "", "vif_fat32", vif_fat32))
            `uvm_fatal("TEST", "Failed to get vif_fat32")

        // 生成参考图像 (与 fat32_image_gen::write_file_data 完全一致的公式)
        generate_ref_image();

        // 将 ref_image 通过 config_db 传给 env → scoreboard
        if (!skip_ram_compare)
            uvm_config_db#(int)::set(this, "env", "ref_image_valid", 1);
    endfunction

    // 生成参考图像: 必须与 fat32_image_gen::write_file_data 的图案公式完全一致
    virtual function void generate_ref_image();
        for (int y = 0; y < 240; y++) begin
            for (int x = 0; x < 320; x++) begin
                int idx = y * 320 + x;
                bit [2:0] r3 = (x * 7) / 319;
                bit [2:0] g3 = (y * 7) / 239;
                bit [1:0] b2 = ((x + y) * 3) / (319 + 239);
                ref_image[idx] = {r3, g3, b2};
            end
        end
    endfunction

    // end_of_elaboration: 将 ref_image 注入 scoreboard (组件已全部创建)
    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        if (!skip_ram_compare) begin
            env.m_fat32_sb.ref_image       = ref_image;
            env.m_fat32_sb.ref_image_valid = 1;
            env.m_vga_sb.ref_image         = ref_image;
            env.m_vga_sb.ref_image_valid   = 1;
        end
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_test_body(phase);
        phase.drop_objection(this);
    endtask

    virtual task run_test_body(uvm_phase phase);
    endtask

    // 等待 read_done 上升沿，或超时报错
    task wait_read_done(input time timeout = 50ms);
        `uvm_info("TEST", $sformatf("Waiting for read_done (timeout=%0t)...", timeout), UVM_MEDIUM)
        fork : wait_or_timeout
            begin
                @(posedge vif_fat32.read_done);
                `uvm_info("TEST", "read_done asserted", UVM_MEDIUM)
            end
            begin
                #(timeout);
                `uvm_error("TEST", $sformatf("TIMEOUT: read_done not asserted within %0t", timeout))
            end
        join_any
        disable wait_or_timeout;
    endtask

    // 等待 file_found 上升沿，或超时
    task wait_file_found(input time timeout = 50ms);
        `uvm_info("TEST", "Waiting for file_found...", UVM_MEDIUM)
        fork : wait_ff
            begin
                @(posedge vif_fat32.file_found);
                `uvm_info("TEST", "file_found asserted", UVM_MEDIUM)
            end
            begin
                #(timeout);
                `uvm_info("TEST", "file_found not asserted (may be expected)", UVM_MEDIUM)
            end
        join_any
        disable wait_ff;
    endtask

    // 等待指定数量的 VGA 帧 (通过 vsync 下降沿计数)
    task wait_vga_frames(input int num_frames = 2);
        virtual sd_sys_if.vga_mon vif_vga;
        if (!uvm_config_db#(virtual sd_sys_if.vga_mon)::get(this, "", "vif_vga", vif_vga)) begin
            `uvm_warning("TEST", "vif_vga not available, using delay instead")
            #(num_frames * 17_000_000);  // ~17ms per frame @ 60Hz
            return;
        end
        `uvm_info("TEST", $sformatf("Waiting for %0d VGA frame(s)...", num_frames), UVM_MEDIUM)
        repeat (num_frames) @(negedge vif_vga.vga_vs);
        `uvm_info("TEST", $sformatf("%0d VGA frame(s) completed", num_frames), UVM_MEDIUM)
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

    virtual task run_test_body(uvm_phase phase);
        // 等待 FAT32 文件读取完成
        wait_read_done(3s);  // 3s timeout

        // 检查 file_found 已被置位
        if (!vif_fat32.file_found)
            `uvm_error("TEST", "read_done asserted but file_found is 0")

        // 等待 2 个 VGA 帧完成像素比对
        `uvm_info("TEST", "sys_normal_test: Waiting 2 VGA frames for pixel compare...", UVM_MEDIUM)
        wait_vga_frames(2);

        `uvm_info("TEST", "sys_normal_test: run_phase complete, scoreboard will report in report_phase", UVM_NONE)
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
        // 跳过 RAM/VGA 比对 (卡内无文件，RAM 不会被写入有意义的数据)
        skip_ram_compare = 1;

        super.build_phase(phase);

        // 通知 TB top 生成无 IMAGE.BIN 的镜像
        // TB top 应检查此 config_db 项并调用 fat32_image_gen::generate_image(..., 0)
        uvm_config_db#(bit)::set(null, "", "fat32_no_file", 1);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        // 等待足够时间让 DUT 完成目录扫描 (无法等 read_done 因为不会置位)
        `uvm_info("TEST", "sys_no_file_test: Waiting for DUT to finish directory scan...", UVM_MEDIUM)
        #20_000_000;  // 20ms

        // 检查 file_found 未置位
        if (vif_fat32.file_found)
            `uvm_error("TEST", "file_found should be 0 when IMAGE.BIN is absent")
        else
            `uvm_info("TEST", "PASS: file_found=0 as expected (no IMAGE.BIN)", UVM_NONE)

        // 检查 read_done 未置位
        if (vif_fat32.read_done)
            `uvm_error("TEST", "read_done should be 0 when IMAGE.BIN is absent")
        else
            `uvm_info("TEST", "PASS: read_done=0 as expected", UVM_NONE)
    endtask
endclass : sys_no_file_test

// -----------------------------------------------------------------------------
// Cluster Size Test: 不同 sectors_per_cluster
// -----------------------------------------------------------------------------
// 注意: 当前 fat32_image_gen 的 SECTORS_PER_CLUSTER 为编译期参数。
//       要测试不同值 (1, 8, 32, 64)，需要:
//       方案 A: 每次用不同 +define 重新编译 (推荐回归脚本实现)
//       方案 B: 重构 fat32_image_gen 为运行时可配置 (传参)
//       当前实现: 以默认 spc=8 运行，验证端到端正确性。
class sys_cluster_size_test extends sys_base_test;
    `uvm_component_utils(sys_cluster_size_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        `uvm_info("TEST", $sformatf(
            "sys_cluster_size_test: running with compile-time spc=%0d",
            fat32_image_gen::SECTORS_PER_CLUSTER), UVM_MEDIUM)

        wait_read_done(100_000_000);

        if (!vif_fat32.file_found)
            `uvm_error("TEST", "file_found not asserted")

        // 等待 1 个 VGA 帧验证像素
        wait_vga_frames(1);

        `uvm_info("TEST", $sformatf(
            "sys_cluster_size_test: spc=%0d passed",
            fat32_image_gen::SECTORS_PER_CLUSTER), UVM_NONE)
    endtask
endclass : sys_cluster_size_test

// -----------------------------------------------------------------------------
// Partition LBA Test: 不同 MBR 分区起始 LBA
// -----------------------------------------------------------------------------
// 注意: 同 cluster_size_test，PARTITION_START_LBA 为编译期参数。
//       要测试 0x800 / 0x2000 / 0x8000，需分别编译或重构生成器。
class sys_partition_lba_test extends sys_base_test;
    `uvm_component_utils(sys_partition_lba_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        `uvm_info("TEST", $sformatf(
            "sys_partition_lba_test: running with compile-time lba=0x%0X",
            fat32_image_gen::PARTITION_START_LBA), UVM_MEDIUM)

        wait_read_done(100_000_000);

        if (!vif_fat32.file_found)
            `uvm_error("TEST", "file_found not asserted")

        wait_vga_frames(1);

        `uvm_info("TEST", $sformatf(
            "sys_partition_lba_test: lba=0x%0X passed",
            fat32_image_gen::PARTITION_START_LBA), UVM_NONE)
    endtask
endclass : sys_partition_lba_test

// -----------------------------------------------------------------------------
// Reserved Sectors Test
// -----------------------------------------------------------------------------
// 注意: RESERVED_SECTORS 为编译期参数，默认 32。
//       测试较大值 (如 128) 需重编译。
class sys_reserved_sec_test extends sys_base_test;
    `uvm_component_utils(sys_reserved_sec_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        `uvm_info("TEST", $sformatf(
            "sys_reserved_sec_test: running with compile-time reserved=%0d",
            fat32_image_gen::RESERVED_SECTORS), UVM_MEDIUM)

        wait_read_done(100_000_000);

        if (!vif_fat32.file_found)
            `uvm_error("TEST", "file_found not asserted")

        if (!vif_fat32.read_done)
            `uvm_error("TEST", "read_done not asserted")

        wait_vga_frames(1);

        `uvm_info("TEST", $sformatf(
            "sys_reserved_sec_test: reserved=%0d passed",
            fat32_image_gen::RESERVED_SECTORS), UVM_NONE)
    endtask
endclass : sys_reserved_sec_test

`endif // SD_SYS_TESTS_SV
