// Transparent clock-gate model, replacing cores/cv32e40p/bhv/cv32e40p_sim_clock_gate.sv.
// yosys prove mode does not accept a derived (gated) clock without clk2fflogic.
// Holding the gate open is an over-approximation: every state the gated design can
// reach is still reachable here, so an unreachability proof remains sound.
// It is not sound for clock-gating or power properties, which are out of scope here.
module cv32e40p_clock_gate (
    input  logic clk_i,
    input  logic en_i,
    input  logic scan_cg_en_i,
    output logic clk_o
);
  assign clk_o = clk_i;
endmodule
