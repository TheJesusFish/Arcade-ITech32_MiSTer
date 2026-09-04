// SPDX-License-Identifier: GPL-3.0-or-later
// One automatic NVRAM save request per OSD-opening edge.
`timescale 1ns/1ps

module itech32_nvram_save_request (
	input  logic clk,
	input  logic reset,
	input  logic dirty,
	input  logic osd_status,
	output logic upload_req
);
	logic osd_status_d = 1'b0;

	always_ff @(posedge clk) begin
		if (reset) begin
			osd_status_d <= 1'b0;
			upload_req <= 1'b0;
		end else begin
			osd_status_d <= osd_status;
			upload_req <= dirty && osd_status && !osd_status_d;
		end
	end
endmodule
