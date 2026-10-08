// axi4_lite_protocol_sva.sv
//
// Generic AMBA AXI4-Lite protocol checks, bound directly to the
// `axi4_lite_if` interface TYPE (not any specific module instance) --
// SystemVerilog's `bind` applies this to every instance of the interface
// anywhere in the design automatically: the testbench's `s_axi`, and each
// of the four internal peripheral-facing interface instances inside
// `soc_peripheral_subsystem_top`. No per-instance wiring needed.
//
// These check the bus PROTOCOL itself (VALID/READY stability, no unknown
// values), independent of any particular peripheral's register semantics
// -- those are checked functionally by the testbench's directed checks
// instead.

module axi4_lite_protocol_checker (
    input logic clk,
    input logic rstn,

    input logic awvalid, awready,
    input logic wvalid,  wready,
    input logic bvalid,  bready,
    input logic [1:0] bresp,

    input logic arvalid, arready,
    input logic rvalid,  rready,
    input logic [1:0] rresp
);

    // Once VALID is asserted and READY hasn't come yet, VALID must stay
    // asserted until the transfer completes (AXI4 stability rule) --
    // applies to whichever side is driving that channel's VALID.
    property p_valid_stable(logic valid, logic ready);
        @(posedge clk) disable iff (!rstn)
        (valid && !ready) |=> valid;
    endproperty

    a_awvalid_stable: assert property (p_valid_stable(awvalid, awready))
        else $error("[SVA] AWVALID dropped before AWREADY");
    a_wvalid_stable: assert property (p_valid_stable(wvalid, wready))
        else $error("[SVA] WVALID dropped before WREADY");
    a_arvalid_stable: assert property (p_valid_stable(arvalid, arready))
        else $error("[SVA] ARVALID dropped before ARREADY");
    a_bvalid_stable: assert property (p_valid_stable(bvalid, bready))
        else $error("[SVA] BVALID dropped before BREADY");
    a_rvalid_stable: assert property (p_valid_stable(rvalid, rready))
        else $error("[SVA] RVALID dropped before RREADY");

    // BRESP/RRESP must not change while their VALID is held waiting on READY.
    property p_resp_stable(logic valid, logic ready, logic [1:0] resp);
        @(posedge clk) disable iff (!rstn)
        (valid && !ready) |=> $stable(resp);
    endproperty

    a_bresp_stable: assert property (p_resp_stable(bvalid, bready, bresp))
        else $error("[SVA] BRESP changed while BVALID held");
    a_rresp_stable: assert property (p_resp_stable(rvalid, rready, rresp))
        else $error("[SVA] RRESP changed while RVALID held");

    // No unknown VALID/READY values once out of reset -- an X here almost
    // always means an uninitialized register or a genuine RTL bug, and
    // it's far easier to debug at the point it first appears than several
    // cycles later when it's corrupted a data value.
    a_no_x_awvalid: assert property (@(posedge clk) disable iff (!rstn) !$isunknown(awvalid));
    a_no_x_wvalid:  assert property (@(posedge clk) disable iff (!rstn) !$isunknown(wvalid));
    a_no_x_arvalid: assert property (@(posedge clk) disable iff (!rstn) !$isunknown(arvalid));
    a_no_x_bvalid:  assert property (@(posedge clk) disable iff (!rstn) !$isunknown(bvalid));
    a_no_x_rvalid:  assert property (@(posedge clk) disable iff (!rstn) !$isunknown(rvalid));

endmodule : axi4_lite_protocol_checker

bind axi4_lite_if axi4_lite_protocol_checker u_axi4_lite_protocol_checker (.*);
