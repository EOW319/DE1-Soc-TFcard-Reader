// =============================================================================
// sd_sys_scoreboard.sv
// Layer 3 — 全系统端到端检查器
//
// 功能 1: FAT32 Scoreboard — 监控 sd_file_reader 写入 img_ram 的数据
//           与 SD 卡模型 IMAGE.BIN 数据逐字节比对 (76800 字节)
//           检查 file_found / read_done 标志正确置位
//
// 功能 2: VGA Frame Checker — 从 VGA Monitor 接收重建的 320×240 帧
//           与原始 IMAGE.BIN 数据进行 RGB332 像素级比对
// =============================================================================
`ifndef SD_SYS_SCOREBOARD_SV
`define SD_SYS_SCOREBOARD_SV

// 图像帧 item (由 VGA Monitor 发布)
class vga_frame_item extends uvm_sequence_item;
    `uvm_object_utils(vga_frame_item)
    byte unsigned pixels[76800];   // 320×240 × 8-bit RGB332

    function new(string name = "vga_frame_item");
        super.new(name);
    endfunction
endclass

// RAM 写 item (由 FAT32 Monitor 发布)
class ram_write_item extends uvm_sequence_item;
    `uvm_object_utils(ram_write_item)
    bit [16:0] addr;
    bit [7:0]  data;
    function new(string name = "ram_write_item");
        super.new(name);
    endfunction
endclass

// -----------------------------------------------------------------------------
// FAT32 Scoreboard
// -----------------------------------------------------------------------------
class fat32_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(fat32_scoreboard)

    uvm_analysis_imp #(ram_write_item, fat32_scoreboard) ram_mon_export;

    byte unsigned ref_image[76800];  // IMAGE.BIN 参考数据 (由 test 注入)
    byte unsigned actual_ram[76800]; // 收集到的 RAM 写入数据
    bit           written[76800];    // 标记每个地址是否被写入

    int unsigned fail_cnt;
    bit          file_found_seen;
    bit          read_done_seen;
    bit          ref_image_valid;    // test 注入 ref_image 后置 1

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ram_mon_export    = new("ram_mon_export", this);
        fail_cnt          = 0;
        file_found_seen   = 0;
        read_done_seen    = 0;
        ref_image_valid   = 0;
        foreach (written[i]) written[i] = 0;
    endfunction

    // 每次 RAM 写事件
    function void write(ram_write_item item);
        if (item.addr >= 76800) begin
            `uvm_error("FAT32SB", $sformatf("RAM write addr 0x%0X out of range (max 76799)", item.addr))
            fail_cnt++;
            return;
        end
        actual_ram[item.addr] = item.data;
        written[item.addr]    = 1;
    endfunction

    // 在 report_phase 进行最终比对
    function void report_phase(uvm_phase phase);
        int mismatch = 0;
        int not_written = 0;

        if (!ref_image_valid) begin
            `uvm_warning("FAT32SB", "ref_image not set, skipping comparison")
            return;
        end

        for (int i = 0; i < 76800; i++) begin
            if (!written[i]) begin
                not_written++;
            end else if (actual_ram[i] !== ref_image[i]) begin
                if (mismatch < 10)
                    `uvm_error("FAT32SB", $sformatf(
                        "RAM[%0d] mismatch: got 0x%02X, exp 0x%02X", i, actual_ram[i], ref_image[i]))
                mismatch++;
            end
        end

        if (not_written > 0)
            `uvm_error("FAT32SB", $sformatf("%0d RAM addresses never written", not_written))

        if (mismatch > 0)
            `uvm_error("FAT32SB", $sformatf("Total %0d byte mismatches in img_ram", mismatch))

        if (!file_found_seen)
            `uvm_error("FAT32SB", "file_found was never asserted")

        if (!read_done_seen)
            `uvm_error("FAT32SB", "read_done was never asserted")

        if (mismatch == 0 && not_written == 0 && file_found_seen && read_done_seen)
            `uvm_info("FAT32SB", "PASS: Full 76800-byte IMAGE.BIN match confirmed", UVM_NONE)
    endfunction

endclass : fat32_scoreboard

// -----------------------------------------------------------------------------
// VGA Frame Scoreboard
// -----------------------------------------------------------------------------
class vga_frame_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(vga_frame_scoreboard)

    uvm_analysis_imp #(vga_frame_item, vga_frame_scoreboard) vga_mon_export;

    byte unsigned ref_image[76800];  // IMAGE.BIN 参考 (由 test 注入)
    int unsigned  frame_cnt;
    int unsigned  fail_cnt;
    bit           ref_image_valid;    // test 注入 ref_image 后置 1

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        vga_mon_export = new("vga_mon_export", this);
        frame_cnt = 0;
        fail_cnt  = 0;
        ref_image_valid = 0;
    endfunction

    function void write(vga_frame_item item);
        int mismatch = 0;
        frame_cnt++;

        if (!ref_image_valid) begin
            `uvm_warning("VGASB", "ref_image not set, skipping pixel comparison")
            return;
        end

        for (int i = 0; i < 76800; i++) begin
            if (item.pixels[i] !== ref_image[i]) begin
                if (mismatch < 10)
                    `uvm_error("VGASB", $sformatf(
                        "Frame %0d pixel[%0d] mismatch: got 0x%02X, exp 0x%02X",
                        frame_cnt, i, item.pixels[i], ref_image[i]))
                mismatch++;
            end
        end

        if (mismatch == 0)
            `uvm_info("VGASB", $sformatf("Frame %0d PASS: 320x240 pixel match", frame_cnt), UVM_MEDIUM)
        else
            fail_cnt++;
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("VGASB", $sformatf("VGA Scoreboard: %0d frames checked, %0d fail", frame_cnt, fail_cnt), UVM_NONE)
        if (fail_cnt > 0)
            `uvm_error("VGASB", "VGA Frame Scoreboard detected FAILURES")
    endfunction

endclass : vga_frame_scoreboard

`endif // SD_SYS_SCOREBOARD_SV
