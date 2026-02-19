// =============================================================================
// sd_reader_scoreboard.sv
// Layer 2 — sd_reader 扇区数据逐字节比对
//
// 接收: sd_reader_mon_item (从 Agent Monitor AP)
// 参考: SD 卡模型内部 memory，通过 config_db 传入指针或 mailbox
//
// 检查: 512 字节数据与 sd_card_model.mem[sector*512 : sector*512+511] 一一比对
// =============================================================================
`ifndef SD_READER_SCOREBOARD_SV
`define SD_READER_SCOREBOARD_SV

class sd_reader_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(sd_reader_scoreboard)

    uvm_analysis_imp #(sd_reader_mon_item, sd_reader_scoreboard) mon_export;

    // SD 卡模型 memory 引用 (由 test 通过 config_db 注入)
    // 使用 byte 动态数组表示磁盘镜像
    byte unsigned card_mem[];
    int unsigned  total_sectors;

    int unsigned pass_cnt;
    int unsigned fail_cnt;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon_export = new("mon_export", this);
        pass_cnt   = 0;
        fail_cnt   = 0;
        // TODO: 从 config_db 获取 card_mem 引用
        // uvm_config_db #(byte unsigned[])::get(this, "", "card_mem", card_mem);
    endfunction

    function void write(sd_reader_mon_item item);
        int base;
        bit err = 0;

        if (card_mem.size() == 0) begin
            `uvm_warning("SB", "card_mem not set, skipping byte comparison")
            return;
        end

        base = item.sector * 512;
        if (base + 512 > card_mem.size()) begin
            `uvm_error("SB", $sformatf("Sector 0x%08X out of card_mem range", item.sector))
            fail_cnt++;
            return;
        end

        // 字节比对
        for (int i = 0; i < 512; i++) begin
            if (item.data[i] !== card_mem[base + i]) begin
                `uvm_error("SB", $sformatf(
                    "Byte mismatch @ sector=0x%X offset=%0d: got 0x%02X, exp 0x%02X",
                    item.sector, i, item.data[i], card_mem[base + i]))
                err = 1;
                if (fail_cnt + 1 > 10) break;  // 最多报 10 个字节错误
            end
        end

        if (item.byte_count !== 512) begin
            `uvm_error("SB", $sformatf("Byte count mismatch: got %0d, exp 512", item.byte_count))
            err = 1;
        end

        if (!err) begin
            pass_cnt++;
            `uvm_info("SB", $sformatf("PASS [%0d]: sector=0x%08X 512B verified", pass_cnt, item.sector), UVM_HIGH)
        end else begin
            fail_cnt++;
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SB", $sformatf("sd_reader Scoreboard: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt), UVM_NONE)
        if (fail_cnt > 0)
            `uvm_error("SB", "sd_reader Scoreboard detected FAILURES")
    endfunction

endclass : sd_reader_scoreboard

`endif // SD_READER_SCOREBOARD_SV
