`timescale 1ns/1ps

// Exercise the complete WIDE=1 hps_io upload/download schedule against the
// real synchronous SFTM NVRAM banks. This catches word-address skew which a
// direct host-port test cannot observe.
module itech32_nvram_transfer_tb;
	localparam int WORDS = 16;

	logic clk = 1'b0;
	logic reset = 1'b1;
	logic new_game = 1'b0;
	logic fp_enable = 1'b0;
	logic io_strobe = 1'b0;
	logic [15:0] io_din = 16'd0;
	tri [45:0] hps_bus;
	tri [35:0] ext_bus;

	wire ioctl_download;
	wire ioctl_upload;
	wire ioctl_wr;
	wire ioctl_rd;
	wire [15:0] ioctl_index;
	wire [26:0] ioctl_addr;
	wire [15:0] ioctl_dout;
	wire [15:0] ioctl_din;
	wire ioctl_wait;
	wire memory_access;
	wire memory_write;
	wire [16:0] memory_addr;
	wire [15:0] memory_din;
	wire [15:0] memory_dout;
	wire runtime_hold;
	wire dirty;
	wire nvram_cpu_write;
	logic [15:0] expected [0:WORDS-1];

	assign hps_bus[45:38] = 8'd0;
	assign hps_bus[35] = fp_enable;
	assign hps_bus[34] = 1'b0;
	assign hps_bus[33] = io_strobe;
	assign hps_bus[31:16] = io_din;
	assign ext_bus[32] = 1'b0;

	/* verilator lint_off PINMISSING */
	hps_io #(.CONF_STR("TEST;;"), .WIDE(1)) hps (
		.clk_sys(clk), .HPS_BUS(hps_bus), .EXT_BUS(ext_bus), .gamma_bus(),
		.ioctl_download(ioctl_download), .ioctl_upload(ioctl_upload),
		.ioctl_wr(ioctl_wr), .ioctl_rd(ioctl_rd), .ioctl_index(ioctl_index),
		.ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
		.ioctl_din(ioctl_din), .ioctl_wait(ioctl_wait),
		.ioctl_upload_req(1'b0), .ioctl_upload_index(8'h02)
	);
	/* verilator lint_on PINMISSING */

	itech32_nvram_io nvram_io (
		.clk(clk), .reset(reset), .new_game(new_game),
		.ioctl_download(ioctl_download), .ioctl_upload(ioctl_upload),
		.ioctl_wr(ioctl_wr), .ioctl_index(ioctl_index),
		.ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
		.cpu_write(nvram_cpu_write), .memory_dout(memory_dout),
		.memory_access(memory_access), .memory_write(memory_write),
		.memory_addr(memory_addr), .memory_din(memory_din),
		.ioctl_din(ioctl_din), .ioctl_wait(ioctl_wait),
		.runtime_hold(runtime_hold), .dirty(dirty)
	);

	/* verilator lint_off PINCONNECTEMPTY */
	itech32_main_bus memory (
		.clk(clk), .reset(reset), .timekill_mode(1'b0),
		.bloodstorm_mode(1'b0), .rom_buffer_invalidate(1'b0),
		.cpu_req(1'b0), .cpu_we(1'b0), .cpu_addr(24'd0),
		.cpu_wdata(32'd0), .cpu_be(4'd0), .cpu_ack(), .cpu_rdata(),
		.input_p1(32'd0), .input_p2(32'd0), .input_p3(32'd0),
		.input_p4(32'd0), .input_dips(32'd0), .input_extra(32'd0),
		.protection_address(15'h7a6a),
		.nvram_host_access(memory_access), .nvram_host_write(memory_write),
		.nvram_host_addr(memory_addr), .nvram_host_wdata(memory_din),
		.nvram_host_rdata(memory_dout), .nvram_cpu_write(nvram_cpu_write),
		.video_req(), .video_we(), .video_addr(), .video_wdata(),
		.video_be(), .video_ack(1'b0), .video_rdata(16'd0),
		.rom_req(), .rom_addr(), .rom_ack(1'b0), .rom_rdata(32'd0),
		.sound_command_valid(), .sound_command(), .watchdog_strobe(),
		.vint_ack_strobe(), .special_read_strobe(), .color0_strobe(),
		.color1_strobe(), .color_data(), .plane_enable(), .grom_bank(),
		.palette_video_addr(15'd0), .palette_video_rgb()
	);
	/* verilator lint_on PINCONNECTEMPTY */

	always #5 clk = ~clk;

	task automatic fp_begin;
		@(negedge clk);
		fp_enable = 1'b1;
	endtask

	task automatic fp_word(input logic [15:0] value);
		@(negedge clk);
		io_din = value;
		io_strobe = 1'b1;
		@(negedge clk);
		io_strobe = 1'b0;
	endtask

	task automatic fp_end;
		@(negedge clk);
		fp_enable = 1'b0;
		repeat (2) @(negedge clk);
	endtask

	task automatic set_index(input logic [15:0] index);
		fp_begin();
		fp_word(16'h0055);
		fp_word(index);
		fp_end();
	endtask

	task automatic set_transfer(input logic [7:0] request);
		fp_begin();
		fp_word(16'h0053);
		fp_word({8'd0, request});
		fp_end();
	endtask

	task automatic begin_data;
		fp_begin();
		// ioctl_wait stalls acknowledgement, not the first request edge. The
		// command is therefore accepted while the initial BRAM read settles.
		fp_word(16'h0054);
	endtask

	task automatic wait_ready;
		integer edges;
		begin
			edges = 0;
			while (ioctl_wait) begin
				@(posedge clk); #1;
				edges = edges + 1;
				if (edges > 20) $fatal(1, "NVRAM_TRANSFER_WAIT_TIMEOUT");
			end
		end
	endtask

	initial begin
		#500000;
		$fatal(1, "NVRAM_TRANSFER_GLOBAL_TIMEOUT");
	end

	initial begin
		for (int i = 0; i < WORDS; i++)
			expected[i] = 16'h3100 ^ (i * 16'h0411);
		// Distinct battery-valid-style sentinels make a one-word skew obvious.
		expected[6] = 16'hffff;
		expected[7] = 16'h5aa5;

		repeat (4) @(negedge clk);
		reset = 1'b0;
		set_index(16'h0002);
		set_transfer(8'hff);
		assert (ioctl_download) else $fatal(1, "NVRAM_DOWNLOAD_NOT_ACTIVE");
		begin_data();
		for (int i = 0; i < WORDS; i++)
			fp_word(expected[i]);
		fp_end();
		set_transfer(8'h00);
		assert (!ioctl_download) else $fatal(1, "NVRAM_DOWNLOAD_NOT_STOPPED");

		set_index(16'h0002);
		set_transfer(8'haa);
		assert (ioctl_upload && runtime_hold) else
			$fatal(1, "NVRAM_UPLOAD_NOT_ACTIVE");
		begin_data();
		for (int i = 0; i < WORDS; i++) begin
			wait_ready();
			fp_word(16'd0);
			#1;
			assert (hps_bus[15:0] === expected[i]) else
				$fatal(1, "NVRAM_TRANSFER_SKEW word=%0d addr=%05x got=%04x expected=%04x",
					i, ioctl_addr, hps_bus[15:0], expected[i]);
		end
		fp_end();
		set_transfer(8'h00);

		$display("NVRAM_TRANSFER_PASS words=%0d exact_round_trip=ok", WORDS);
		$finish;
	end
endmodule
