// SPDX-License-Identifier: GPL-3.0-or-later
// Must Shoot TV's light-gun interrupts (MAME shoottv_state::gun_interrupt).
//
// At the start of every raster line MAME raises 68020 level 5 when
// (vpos & 0x1f) == 0 and level 6 when it is 16. Each stays asserted until the
// game reads its clear window (level 6: 0x183000; level 5: 0x183800-0x188003).
`timescale 1ns/1ps

module itech32_gun_irq (
	input  logic       clk,
	input  logic       reset,
	input  logic       enable,
	// One clock at the first pixel of each raster line.
	input  logic       line_start,
	input  logic [9:0] vpos,
	input  logic       ack5,
	input  logic       ack6,
	output logic [2:0] irq_level
);
	logic irq5_q;
	logic irq6_q;

	always_ff @(posedge clk) begin
		if (reset || !enable) begin
			irq5_q <= 1'b0;
			irq6_q <= 1'b0;
		end else begin
			if (line_start && vpos[4:0] == 5'd0)
				irq5_q <= 1'b1;
			else if (ack5)
				irq5_q <= 1'b0;
			if (line_start && vpos[4:0] == 5'd16)
				irq6_q <= 1'b1;
			else if (ack6)
				irq6_q <= 1'b0;
		end
	end

	assign irq_level = irq6_q ? 3'd6 : irq5_q ? 3'd5 : 3'd0;
endmodule
