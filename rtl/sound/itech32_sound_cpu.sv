// SPDX-License-Identifier: GPL-3.0-or-later
//
// Minimal ITech32 sound-board CPU wrapper around Greg Miller's mc6809i.
// The external memory contract is deliberately technology independent:
// mem_valid and the request payload remain asserted until mem_ready is high.

`timescale 1ns/1ps

module itech32_sound_cpu #(
	parameter ILLEGAL_INSTRUCTIONS = "GHOST"
) (
	input  logic         clk,
	input  logic         reset,
	input  logic         ce_8m,

	output logic         mem_valid,
	output logic [15:0]  mem_addr,
	output logic         mem_write,
	output logic [7:0]   mem_wdata,
	input  logic [7:0]   mem_rdata,
	input  logic         mem_ready,

	input  logic         irq,
	input  logic         firq,
	input  logic         nmi,

	output logic         ce_e,
	output logic         ce_q,
	output logic         ce_cpu_2m,
	output logic [1:0]   phase,
	output logic         opcode_fetch,
	output logic         bus_status,
	output logic         bus_available,
	output logic         cpu_busy,
	output logic         last_instruction_cycle,
	output logic [111:0] debug_regs
);

	logic       core_rnw;
	logic       core_avma;
	logic       core_op;
	logic       core_bs;
	logic       core_ba;
	logic       core_busy;
	logic       core_lic;
	logic       wait_hold;

	assign mem_write              = ~core_rnw;
	assign opcode_fetch           = core_op;
	assign bus_status             = core_bs;
	assign bus_available          = core_ba;
	assign cpu_busy               = core_busy;
	assign last_instruction_cycle = core_lic;

	// AVMA describes the bus cycle that becomes active after an E edge. Latch
	// it exactly as the established JTFRAME 6809 wrapper does. The resulting
	// request is stable through Q and until the following accepted E edge.
	always_ff @(posedge clk) begin
		if (reset)
			mem_valid <= 1'b1;
		else if (ce_e)
			mem_valid <= core_avma;
	end

	// Only E/Q phases can change CPU state or consume the active request.
	// Let the intervening inactive phase elapse while memory responds, but
	// never issue either active edge before ready. This overlaps bus latency
	// with the existing four-phase cadence without raising the CPU clock.
	assign wait_hold = mem_valid && !mem_ready && !phase[0];

	itech32_6809_phase_enable phase_enable (
		.clk       (clk),
		.reset     (reset),
		.ce_8m     (ce_8m),
		.hold      (wait_hold),
		.ce_e      (ce_e),
		.ce_q      (ce_q),
		.ce_cpu_2m (ce_cpu_2m),
		.phase     (phase)
	);

	mc6809i #(
		.ILLEGAL_INSTRUCTIONS(ILLEGAL_INSTRUCTIONS)
	) cpu (
		.D        (mem_rdata),
		.DOut     (mem_wdata),
		.ADDR     (mem_addr),
		.RnW      (core_rnw),
		.clk      (clk),
		.cen_E    (ce_e),
		.cen_Q    (ce_q),
		.BS       (core_bs),
		.BA       (core_ba),
		.nIRQ     (~irq),
		.nFIRQ    (~firq),
		.nNMI     (~nmi),
		.AVMA     (core_avma),
		.BUSY     (core_busy),
		.LIC      (core_lic),
		.nHALT    (1'b1),
		.nRESET   (~reset),
		.nDMABREQ (1'b1),
		.OP       (core_op),
		.RegData  (debug_regs)
	);

endmodule
