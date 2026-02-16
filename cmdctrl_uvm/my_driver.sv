`ifndef MYDRIVER_SV
`define MYDRIVER_SV
class my_driver extends uvm_driver #(cmdctrl_txd);
    virtual sdcmd_if.drv vif;
    `uvm_component_utils(my_driver)

    function new(string name="my_driver", uvm_component parent=null);
        super.new(name, parent);
    endfunction //new()

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual sdcmd_if.drv)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Virtual interface must be set for: " 
                        , $sformatf("%s", get_full_name()))
        end
    endfunction //build_phase()

    extern task main_phase(uvm_phase phase);
    extern task automatic drive_idle();
    extern task automatic drive_one(cmdctrl_txd t);
endclass //my_driver extends uvm_driver #(cmdctrl_txd)

task my_driver::main_phase(uvm_phase phase);
    cmdctrl_txd txd_item;

    forever begin
        seq_item_port.get_next_item(txd_item);
        `uvm_info("DRV", {"drive txd: ", txd_item.convert2string()}, UVM_MEDIUM)

        // drive signals to DUT
        drive_one(txd_item);
        do begin
            @(posedge vif.clk);
            if (vif.rstn != 1) begin
                drive_idle();
                break;
            end
        end while (!(vif.done || vif.timeout || vif.syntaxe));
        `uvm_info("DRV", "transaction done", UVM_MEDIUM)
        vif.start <= 1'b0;
        seq_item_port.item_done();
    end
endtask

task automatic my_driver::drive_idle();
    vif.start  <= 1'b0;
    vif.cmd    <= '0;
    vif.arg    <= '0;
    vif.clkdiv <= 16'd1;
    vif.precnt <= '0;
endtask

task automatic my_driver::drive_one(cmdctrl_txd t);
    while (vif.rstn !== 1'b1) begin
      @(posedge vif.clk);
    end

    while (vif.busy === 1'b1) begin
      @(posedge vif.clk);
    end

    // drive transaction signals
    vif.cmd    <= t.cmd;
    vif.arg    <= t.arg;
    vif.clkdiv <= t.clkdiv;
    vif.precnt <= t.precnt;

    @(posedge vif.clk);
    vif.start <= 1'b1;
    @(posedge vif.clk);
    vif.start <= 1'b0;
  endtask

`endif // MYDRIVER_SV