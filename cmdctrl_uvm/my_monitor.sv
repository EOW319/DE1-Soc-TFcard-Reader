`ifndef SDCMD_MONITOR__SV
`define SDCMD_MONITOR__SV
class sdcmd_mon_item extends uvm_sequence_item;
    `uvm_object_utils(sdcmd_mon_item)
    logic [47:0] cmd_bits;
    logic [47:0] resp_bits;
    bit cmd_Exist;
    bit resp_Exist;

    logic [31:0] resparg;
    bit timeout;
    bit syntaxe;
    bit done;
    function new(string name="sdcmd_mon_item");
        super.new(name);
        cmd_bits = 1'0;
        resp_bits = 1'0;
        cmd_Exist = 0;
        resp_Exist = 0;
    endfunction //new()

    function string convert2string();
    return $sformatf("have_cmd=%0b cmd=0x%012h have_resp=%0b resp=0x%012h done=%0b to=%0b syn=%0b resparg=0x%08h",
                     cmd_Exist, cmd_bits, resp_Exist, resp_bits, done, timeout, syntaxe, resparg);
    endfunction


endclass //sdcmd_mon_item extends uvm_sequence_item

class sdcmd_mon extends uvm_monitor;
    `uvm_component_utils(sdcmd_mon)
    virtual sdcmd_if.mon vif;

    uvm_analysis_port #(sdcmd_mon_item) mon_ap;
    // 采样边沿选择：先用 posedge，后面需要再改(?)
    localparam bit SAMPLE_POSEDGE = 1'b1;

    function new(string name="sdcmd_mon", uvm_component parent=null);
        super.new(name, parent);
        mon_ap = new("mon_ap", this);
    endfunction //new()
    extern function void build_phase(uvm_phase phase);
    extern task main_phase(uvm_phase phase);
    extern task automatic wait_sdclk_edge();
endclass //sdcmd_mon extends uvm_monitor
`endif