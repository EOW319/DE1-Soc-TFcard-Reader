`ifndef MYTRANSACTION_SV
`define MYTRANSACTION_SV
class cmdctrl_txd extends uvm_sequence_item;

    rand bit        start_pulse;
    rand bit [5:0]  cmd;
    rand bit [31:0] arg;
    rand bit [15:0] clkdiv;
    rand bit [15:0] precnt;

    bit expect_error;
    bit expect_timeout;

    `uvm_object_utils(cmdctrl_txd)
    
    constraint c_defaults {
        start_pulse == 1'b1;
        clkdiv  inside {[16'd1 : 16'd200]};
        precnt  inside {[16'd46 : 16'd400]};
    }
    constraint c_cmd_basic {
        cmd inside {6'd0, 6'd8, 6'd17, 6'd55, 6'd41};
    }

    `uvm_object_utils_begin(cmdctrl_txd)
        `uvm_field_int(start_pulse, UVM_ALL_ON)
        `uvm_field_int(cmd, UVM_ALL_ON)
        `uvm_field_int(arg, UVM_ALL_ON)
        `uvm_field_int(clkdiv, UVM_ALL_ON)
        `uvm_field_int(precnt, UVM_ALL_ON)
        `uvm_field_int(expect_error, UVM_ALL_ON)
        `uvm_field_int(expect_timeout, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name="cmdctrl_txd", uvm_component parent=null);
        super.new(name, parent);
    endfunction //new()

    function string convert2string();
        return $sformatf("cmd=%0d arg=0x%08h clkdiv=%0d precnt=%0d exp_to=%0b exp_syn=%0b",
                        cmd, arg, clkdiv, precnt, expect_timeout, expect_syntaxe);
    endfunction
endclass //cmdctrl_txd extends uvm_sequence_item

`endif // MYTRANSACTION_SV