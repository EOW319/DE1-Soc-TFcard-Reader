// =============================================================================
// sd_sys_monitor.sv
// Layer 3 — 系统级被动 Monitor (FAT32 + VGA 合并)
//
// fat32_monitor : 采样 sd_file_reader → img_ram 的写操作，
//                 发布 ram_write_item 给 fat32_scoreboard，
//                 监控 file_found / read_done 状态标志。
//
// vga_monitor   : 采样 VGA 输出信号，根据 hsync/vsync 时序
//                 重建 320×240 RGB332 帧，发布 vga_frame_item
//                 给 vga_frame_scoreboard。
// =============================================================================
`ifndef SD_SYS_MONITOR_SV
`define SD_SYS_MONITOR_SV

// =============================================================================
// FAT32 Monitor
// =============================================================================
class fat32_monitor extends uvm_monitor;
    `uvm_component_utils(fat32_monitor)

    // 虚接口 (fat32_mon modport)
    virtual sd_sys_if.fat32_mon vif;

    // analysis port → fat32_scoreboard
    uvm_analysis_port #(ram_write_item) ap;

    // 指向 scoreboard 的句柄，用于直接置位 file_found_seen / read_done_seen
    fat32_scoreboard sb_handle;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);

        if (!uvm_config_db#(virtual sd_sys_if.fat32_mon)::get(this, "", "vif_fat32", vif))
            `uvm_fatal("FAT32MON", "Failed to get vif_fat32")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            monitor_ram_writes();
            monitor_status_flags();
        join
    endtask

    // -------------------------------------------------------------------------
    // 子任务 1: 监控 RAM 写操作
    // -------------------------------------------------------------------------
    // 每个 clk_50 上升沿检查 ram_we，为高时采样 addr/data，
    // 创建 ram_write_item 并通过 ap.write() 发布
    task monitor_ram_writes();
          forever begin
              @(posedge vif.clk_50);
              if (vif.ram_we) begin
                  ram_write_item item = ram_write_item::type_id::create("ram_wr");
                  item.addr = vif.ram_waddr;
                  item.data = vif.ram_wdata;
                  ap.write(item);
              end
          end
    endtask

    // -------------------------------------------------------------------------
    // 子任务 2: 监控 file_found / read_done 状态标志
    // -------------------------------------------------------------------------
    // 检测上升沿后置位 scoreboard 的 file_found_seen / read_done_seen
    task monitor_status_flags();
          fork
              begin  // file_found 上升沿检测
                  @(posedge vif.file_found);
                  `uvm_info("FAT32MON", "file_found asserted", UVM_MEDIUM)
                  if (sb_handle != null) sb_handle.file_found_seen = 1;
              end
              begin  // read_done 上升沿检测
                  @(posedge vif.read_done);
                  `uvm_info("FAT32MON", "read_done asserted", UVM_MEDIUM)
                  if (sb_handle != null) sb_handle.read_done_seen = 1;
              end
          join
    endtask

endclass : fat32_monitor

// =============================================================================
// VGA Monitor
// =============================================================================
class vga_monitor extends uvm_monitor;
    `uvm_component_utils(vga_monitor)

    // 虚接口 (vga_mon modport)
    virtual sd_sys_if.vga_mon vif;

    // analysis port → vga_frame_scoreboard
    uvm_analysis_port #(vga_frame_item) ap;

    // VGA 640×480@60Hz 时序参数
    localparam int H_VISIBLE = 640;
    localparam int H_FRONT   = 16;
    localparam int H_SYNC    = 96;
    localparam int H_BACK    = 48;
    localparam int H_TOTAL   = 800;

    localparam int V_VISIBLE = 480;
    localparam int V_FRONT   = 10;
    localparam int V_SYNC    = 2;
    localparam int V_BACK    = 33;
    localparam int V_TOTAL   = 525;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);

        if (!uvm_config_db#(virtual sd_sys_if.vga_mon)::get(this, "", "vif_vga", vif))
            `uvm_fatal("VGAMON", "Failed to get vif_vga")
    endfunction

    task run_phase(uvm_phase phase);
        capture_frames();
    endtask

    // -------------------------------------------------------------------------
    // 帧捕获主循环
    // -------------------------------------------------------------------------
    // 逻辑:
    //   1. 等待 vsync 下降沿 (帧开始)
    //   2. 跳过 V_SYNC + V_BACK 行
    //   3. 在 V_VISIBLE=480 行中，每行:
    //      a. 等待 hsync 下降沿 (行开始)
    //      b. 跳过 H_SYNC + H_BACK 像素
    //      c. 在 H_VISIBLE=640 像素中采样 vga_r/g/b
    //   4. 将 640×480 缩放还原为 320×240 (2x 放大还原: 取偶数行偶数列)
    //   5. RGB888 → RGB332 反向转换
    //   6. 填充 vga_frame_item.pixels[76800] 并 ap.write()
    task capture_frames();
        forever begin
            vga_frame_item frame;
            byte unsigned  pixel_buf[76800];
            int vis_x, vis_y, px;

            // --- 等待帧开始: vsync 下降沿 ---
            @(negedge vif.vga_vs);

            // --- 逐行逐像素采样 ---
            for (int row = 0; row < V_TOTAL; row++) begin
                for (int col = 0; col < H_TOTAL; col++) begin
                    @(posedge vif.vga_clk);

                    // 判断当前是否在可见区
                    if (row >= (V_SYNC + V_BACK) && row < (V_SYNC + V_BACK + V_VISIBLE) &&
                        col >= (H_SYNC + H_BACK) && col < (H_SYNC + H_BACK + H_VISIBLE)) begin

                        vis_x = col - (H_SYNC + H_BACK);
                        vis_y = row - (V_SYNC + V_BACK);

                        // 2x 放大还原: 只取偶数行偶数列
                        if (vis_x[0] == 0 && vis_y[0] == 0) begin
                            px = (vis_y / 2) * 320 + (vis_x / 2);
                            if (px < 76800)
                                pixel_buf[px] = rgb888_to_rgb332(vif.vga_r, vif.vga_g, vif.vga_b);
                        end
                    end
                end
            end

            // --- 发布帧 ---
            frame = vga_frame_item::type_id::create("vga_frame");
            frame.pixels = pixel_buf;
            ap.write(frame);
            `uvm_info("VGAMON", "Frame captured", UVM_MEDIUM)
        end
    endtask

    // -------------------------------------------------------------------------
    // RGB888 → RGB332 反向转换 (与 DUT 的 RGB332→888 扩展规则匹配)
    // -------------------------------------------------------------------------
    // DUT 扩展规则:
    //   R[7:0] = {rgb332[7:5], rgb332[7:5], rgb332[7:6]}
    //   G[7:0] = {rgb332[4:2], rgb332[4:2], rgb332[4:3]}
    //   B[7:0] = {rgb332[1:0], rgb332[1:0], rgb332[1:0], rgb332[1:0]}
    //
    // 反向: 取高位即可还原
    //   rgb332[7:5] = R[7:5]
    //   rgb332[4:2] = G[7:5]
    //   rgb332[1:0] = B[7:6]
    function byte unsigned rgb888_to_rgb332(
        input logic [7:0] r8,
        input logic [7:0] g8,
        input logic [7:0] b8
    );
        return {r8[7:5], g8[7:5], b8[7:6]};
    endfunction

endclass : vga_monitor

`endif // SD_SYS_MONITOR_SV
