// Formal environment constraints for CV32E40P (open-source flow).
// Mirrors scripts/formal/src/{insn,data,cv32e40p}_assert.sv assumes, written as immediate assumes for yosys.
// Injected into cv32e40p_core (has the OBI ports).
module triage_env_constraints (
  input logic clk, input logic rst_n,
  input logic scan_cg_en_i, input logic fetch_enable_i,
  input logic instr_req_o, input logic instr_gnt_i, input logic instr_rvalid_i,
  input logic data_req_o,  input logic data_gnt_i,  input logic data_rvalid_i);
  reg init = 1;
  always @(posedge clk) init <= 0;
  always @(*) if (init) assume (!rst_n);
  // OBI outstanding counters (saturating 2-bit is enough: core never issues >2 outstanding)
  reg [1:0] i_out, d_out;
  always @(posedge clk or negedge rst_n)
    if (!rst_n) begin i_out <= 0; d_out <= 0; end
    else begin
      if (instr_req_o & instr_gnt_i & ~instr_rvalid_i) i_out <= i_out + 1;
      else if (~(instr_req_o & instr_gnt_i) & instr_rvalid_i) i_out <= i_out - 1;
      if (data_req_o & data_gnt_i & ~data_rvalid_i) d_out <= d_out + 1;
      else if (~(data_req_o & data_gnt_i) & data_rvalid_i) d_out <= d_out - 1;
    end
  always @(*) if (rst_n && !init) begin
    assume (!scan_cg_en_i);                       // no_scan
    assume (fetch_enable_i);                      // core is fetching
    assume (instr_req_o || !instr_gnt_i);         // no_grnt_when_no_req
    assume (i_out != 0 || !instr_rvalid_i);       // no_rvalid_if_no_pending_req
    assume (data_req_o || !data_gnt_i);
    assume (d_out != 0 || !data_rvalid_i);
    assume (i_out != 2'd3 && d_out != 2'd3);      // counters never overflow (bounded outstanding)
  end
endmodule
