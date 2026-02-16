`ifndef SDCMD_SEQUENCER__SV
`define SDCMD_SEQUENCER__SV

class sdcmd_sequencer extends uvm_sequencer #(sdcmd_txn);
  `uvm_component_utils(sdcmd_sequencer)

  function new(string name="sdcmd_sequencer", uvm_component parent=null);
    super.new(name, parent);
  endfunction

endclass : sdcmd_sequencer

`endif // SDCMD_SEQUENCER__SVH
