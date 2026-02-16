`ifndef SDCMD_SEQ__SV
`define SDCMD_SEQ__SV
class sdcmd_single_seq extends uvm_sequence_item #(cmdctrl_txd);
    `uvm_object_utils(sdcmd_single_seq)
    
    bit        use_fixed = 0;
    bit [5:0]  fixed_cmd;
    bit [31:0] fixed_arg;
    bit [15:0] fixed_clkdiv = 16'd1;
    bit [15:0] fixed_precnt = 16'd0;

    function new(string name="sdcmd_single_seq");
        super.new(name);    
    endfunction //new()

    task body();
    cmdctrl_txd t;

    t = cmdctrl_txd::type_id::create("t");

    if (!use_fixed) begin
      if (!t.randomize()) begin
        `uvm_fatal("SEQ", "randomize() failed in sdcmd_single_seq")
      end
      t.expect_timeout = 1'b0;
      t.expect_syntaxe = 1'b0;
    end
    else begin
      t.cmd    = fixed_cmd;
      t.arg    = fixed_arg;
      t.clkdiv = fixed_clkdiv;
      t.precnt = fixed_precnt;

      t.expect_timeout = 1'b0;
      t.expect_syntaxe = 1'b0;
    end

    `uvm_info("SEQ", {"start single txn: ", t.convert2string()}, UVM_MEDIUM)
    start_item(t);
    finish_item(t);
  endtask

endclass //sdcmd_single_seq extends uvm_sequence_item #(cmdctrl_txd)

class sdcmd_rand_seq extends uvm_sequence_item;
  `uvm_object_utils(sdcmd_rand_seq)
  int unsigned item_num = 20;

  function new(string name="sdcmd_rand_seq");
        super.new(name);    
  endfunction //new()
  
  task body();
  cmdctrl_txd t;
  for (int i = 0; i < item_num; i++) begin
    t = cmdctrl_txd::type_id::create("t");
    if (!t.randomize()) begin
      `uvm_fatal("SEQ", "randomize() failed in sdcmd_rand_seq")
    end
    t.expect_timeout = 1'b0;
    t.expect_syntaxe = 1'b0;

    `uvm_info("SEQ", {"start rand txn: ", t.convert2string()}, UVM_MEDIUM)
    start_item(t);
    finish_item(t);
  end
  endtask
endclass //sdcmd_rand_seq extends uvm_sequence_item

`endif //SDCMD_SEQ__SVH