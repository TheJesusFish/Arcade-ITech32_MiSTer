// SPDX-License-Identifier: GPL-3.0-or-later
// MiSTer index-2 persistent-NVRAM transfer control. Storage remains in the
// board RAMs so the game and HPS always observe the same bytes.
`timescale 1ns/1ps

module itech32_nvram_io #(
	parameter logic [15:0] NVRAM_INDEX = 16'h0002,
	parameter integer PREFETCH_CYCLES = 4
) (
	input  logic        clk,
	input  logic        reset,
	input  logic        new_game,
	input  logic        ioctl_download,
	input  logic        ioctl_upload,
	input  logic        ioctl_wr,
	input  logic [15:0] ioctl_index,
	input  logic [26:0] ioctl_addr,
	input  logic [15:0] ioctl_dout,
	input  logic        cpu_write,
	input  logic [15:0] memory_dout,
	output logic        memory_access,
	output logic        memory_write,
	output logic [16:0] memory_addr,
	output logic [15:0] memory_din,
	output logic [15:0] ioctl_din,
	output logic        ioctl_wait,
	output logic        runtime_hold,
	output logic        dirty
);
	localparam integer COUNT_WIDTH = $clog2(PREFETCH_CYCLES + 1);
	logic selected_upload_q = 1'b0;
	logic [16:0] upload_addr_q = 17'd0;
	logic [COUNT_WIDTH-1:0] prefetch_count = COUNT_WIDTH'(PREFETCH_CYCLES);

	wire selected_download = ioctl_download && ioctl_index == NVRAM_INDEX;
	wire selected_upload = ioctl_upload && ioctl_index == NVRAM_INDEX;
	wire upload_address_changed = ioctl_addr[16:0] != upload_addr_q;

	assign memory_access = selected_download || selected_upload;
	assign memory_write = selected_download && ioctl_wr;
	assign memory_addr = ioctl_addr[16:0];
	assign memory_din = ioctl_dout;
	assign ioctl_din = memory_dout;
	assign runtime_hold = selected_upload;
	assign ioctl_wait = selected_upload &&
		(!selected_upload_q || upload_address_changed || prefetch_count != 0);

	always_ff @(posedge clk) begin
		selected_upload_q <= selected_upload;
		if (reset) begin
			upload_addr_q <= 17'd0;
			prefetch_count <= COUNT_WIDTH'(PREFETCH_CYCLES);
			dirty <= 1'b0;
		end else begin
			if (!selected_upload) begin
			upload_addr_q <= ioctl_addr[16:0];
			prefetch_count <= COUNT_WIDTH'(PREFETCH_CYCLES);
			end else if (!selected_upload_q || upload_address_changed) begin
			upload_addr_q <= ioctl_addr[16:0];
			prefetch_count <= COUNT_WIDTH'(PREFETCH_CYCLES);
			end else if (prefetch_count != 0) begin
			prefetch_count <= prefetch_count - 1'b1;
			end

			// A new board image or an HPS restore owns the complete backing
			// store. Clearing on upload start matches established MiSTer cores;
			// no game write can race it because runtime_hold stops both CPUs.
			if (new_game || selected_download ||
				(selected_upload && !selected_upload_q))
				dirty <= 1'b0;
			else if (cpu_write)
				dirty <= 1'b1;
		end
	end
endmodule
