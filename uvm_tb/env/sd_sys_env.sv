// =============================================================================
// sd_sys_env.sv
// Layer 3 — 系统级 UVM Environment
//
// 实例化:
//   fat32_monitor      → fat32_scoreboard    (RAM 写数据比对)
//   vga_monitor        → vga_frame_scoreboard (VGA 帧像素比对)
//
// 参考图像 ref_image 由 test 层通过 config_db 注入，
// env 在 build 时取出并分发给两个 scoreboard。
// =============================================================================
`ifndef SD_SYS_ENV_SV
`define SD_SYS_ENV_SV

class sd_sys_env extends uvm_env;
    `uvm_component_utils(sd_sys_env)

    // 子组件
    fat32_monitor         m_fat32_mon;
    vga_monitor           m_vga_mon;
    fat32_scoreboard      m_fat32_sb;
    vga_frame_scoreboard  m_vga_sb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        m_fat32_mon = fat32_monitor::type_id::create("m_fat32_mon", this);
        m_vga_mon   = vga_monitor::type_id::create("m_vga_mon", this);
        m_fat32_sb  = fat32_scoreboard::type_id::create("m_fat32_sb", this);
        m_vga_sb    = vga_frame_scoreboard::type_id::create("m_vga_sb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // 连接 monitor → scoreboard analysis port
        m_fat32_mon.ap.connect(m_fat32_sb.ram_mon_export);
        m_vga_mon.ap.connect(m_vga_sb.vga_mon_export);

        // 将 scoreboard 句柄传给 fat32_monitor (置位 file_found/read_done)
        m_fat32_mon.sb_handle = m_fat32_sb;
    endfunction

endclass : sd_sys_env

`endif // SD_SYS_ENV_SV
