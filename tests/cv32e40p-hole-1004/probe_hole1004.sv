// HOLE1004 hit-detector probe for cv32e40p_controller.sv:399 FIRST_FETCH condition.
// Expression matches checker_1004.sv (c_hole_irq_and_dbgreq):
//   ctrl_fsm_cs == FIRST_FETCH && irq_req_ctrl_i && debug_req_pending
module hole1004_probe (
  input logic clk, input logic rst_n,
  input cv32e40p_pkg::ctrl_state_e ctrl_fsm_cs,
  input logic irq_req_ctrl_i, input logic debug_req_pending
);
  int unsigned hits;
  initial hits = 0;
  initial $display("HOLE1004_PROBE_LOADED");
  always @(posedge clk) if (rst_n)
    if (ctrl_fsm_cs == cv32e40p_pkg::FIRST_FETCH && irq_req_ctrl_i && debug_req_pending)
      hits <= hits + 1;
  final $display("HOLE1004_HITS=%0d", hits);
endmodule

bind cv32e40p_controller hole1004_probe u_hole1004_probe (
  .clk(clk), .rst_n(rst_n),
  .ctrl_fsm_cs(ctrl_fsm_cs), .irq_req_ctrl_i(irq_req_ctrl_i), .debug_req_pending(debug_req_pending)
);
