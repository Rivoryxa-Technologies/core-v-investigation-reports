// cv32e40p_controller.sv:399  FIRST_FETCH: if (irq_req_ctrl_i && ~(debug_req_pending || debug_mode_q))
// Two uncovered conditions: irq with debug_mode_q=1, irq with debug_req_pending=1.
module triage_chk_1004a import cv32e40p_pkg::*; (
  input logic clk, input logic rst_n, input ctrl_state_e ctrl_fsm_cs,
  input logic irq_req_ctrl_i, input logic debug_mode_q);
  reg init = 1; always @(posedge clk) init <= 0;
  always @(*) if (init) assume (!rst_n);
  always @(posedge clk) if (rst_n && !init)
    a_1004_irq_in_debug_mode: assert (!(ctrl_fsm_cs == FIRST_FETCH && irq_req_ctrl_i && debug_mode_q));
endmodule
module triage_chk_1004b import cv32e40p_pkg::*; (
  input logic clk, input logic rst_n, input ctrl_state_e ctrl_fsm_cs,
  input logic irq_req_ctrl_i, input logic debug_req_pending);
  reg init = 1; always @(posedge clk) init <= 0;
  always @(*) if (init) assume (!rst_n);
  always @(posedge clk) if (rst_n && !init)
    a_1004_irq_with_debug_req: assert (!(ctrl_fsm_cs == FIRST_FETCH && irq_req_ctrl_i && debug_req_pending));
endmodule
module triage_cov_1004 import cv32e40p_pkg::*; (
  input logic clk, input logic rst_n, input ctrl_state_e ctrl_fsm_cs,
  input logic irq_req_ctrl_i, input logic debug_req_pending, input logic debug_mode_q);
  reg init = 1; always @(posedge clk) init <= 0;
  always @(*) if (init) assume (!rst_n);
  always @(posedge clk) if (rst_n && !init) begin
    c_first_fetch_irq: cover (ctrl_fsm_cs == FIRST_FETCH && irq_req_ctrl_i);
    c_first_fetch_dbgreq: cover (ctrl_fsm_cs == FIRST_FETCH && debug_req_pending);
    c_hole_irq_and_dbgreq: cover (ctrl_fsm_cs == FIRST_FETCH && irq_req_ctrl_i && debug_req_pending);
    c_hole_irq_in_dbgmode: cover (ctrl_fsm_cs == FIRST_FETCH && irq_req_ctrl_i && debug_mode_q);
  end
endmodule
