`timescale 1ns/1ps

module itech32_nvram_io_tb;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic new_game = 1'b0;
	logic ioctl_download = 1'b0;
	logic ioctl_upload = 1'b0;
	logic ioctl_wr = 1'b0;
	logic [15:0] ioctl_index = 16'd0;
	logic [26:0] ioctl_addr = 27'd0;
	logic [15:0] ioctl_dout = 16'd0;
	logic cpu_write = 1'b0;
	logic [15:0] memory_dout = 16'd0;
	logic memory_access;
	logic memory_write;
	logic [16:0] memory_addr;
	logic [15:0] memory_din;
	logic [15:0] ioctl_din;
	logic ioctl_wait;
	logic runtime_hold;
	logic dirty;
	integer wait_edges;

	itech32_nvram_io #(.PREFETCH_CYCLES(4)) dut (
		.clk(clk), .reset(reset), .new_game(new_game),
		.ioctl_download(ioctl_download), .ioctl_upload(ioctl_upload),
		.ioctl_wr(ioctl_wr), .ioctl_index(ioctl_index),
		.ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
		.cpu_write(cpu_write), .memory_dout(memory_dout),
		.memory_access(memory_access), .memory_write(memory_write),
		.memory_addr(memory_addr), .memory_din(memory_din), .ioctl_din(ioctl_din),
		.ioctl_wait(ioctl_wait), .runtime_hold(runtime_hold), .dirty(dirty)
	);

	always #5 clk = ~clk;
	always_ff @(posedge clk)
		memory_dout <= {ioctl_addr[7:0] ^ 8'ha5, ioctl_addr[7:0] ^ 8'h5a};

	task automatic pulse(ref logic signal);
		@(negedge clk); signal = 1'b1;
		@(negedge clk); signal = 1'b0;
	endtask

	task automatic wait_for_upload_ready;
		begin
			wait_edges = 0;
			while (ioctl_wait) begin
				@(posedge clk); #1;
				wait_edges = wait_edges + 1;
				if (wait_edges > 10) $fatal(1, "NVRAM_UPLOAD_WAIT_TIMEOUT");
			end
			assert (wait_edges >= 4) else $fatal(1, "NVRAM_UPLOAD_PREFETCH_TOO_SHORT");
		end
	endtask

	initial begin
		repeat (3) @(negedge clk);
		reset = 1'b0;
		pulse(cpu_write);
		assert (dirty) else $fatal(1, "NVRAM_DIRTY_NOT_SET");
		pulse(new_game);
		assert (!dirty) else $fatal(1, "NVRAM_NEW_GAME_NOT_CLEAN");

		@(negedge clk);
		ioctl_index = 16'h0002;
		ioctl_addr = 27'h00124;
		ioctl_dout = 16'hc35a;
		ioctl_download = 1'b1;
		ioctl_wr = 1'b1;
		#1;
		assert (memory_access && memory_write && memory_addr == 17'h00124 && memory_din == 16'hc35a)
			else $fatal(1, "NVRAM_DOWNLOAD_FORWARDING");
		@(negedge clk);
		ioctl_download = 1'b0;
		ioctl_wr = 1'b0;

		pulse(cpu_write);
		@(negedge clk);
		ioctl_addr = 27'h00020;
		ioctl_upload = 1'b1;
		#1;
		assert (runtime_hold && memory_access && ioctl_wait) else $fatal(1, "NVRAM_UPLOAD_START");
		wait_for_upload_ready();
		assert (ioctl_din == 16'h857a) else
			$fatal(1, "NVRAM_UPLOAD_DATA0 got=%04x", ioctl_din);
		assert (!dirty) else $fatal(1, "NVRAM_UPLOAD_NOT_CLEAN");

		@(negedge clk);
		ioctl_addr = 27'h00042;
		#1;
		assert (ioctl_wait) else $fatal(1, "NVRAM_ADDRESS_CHANGE_NO_WAIT");
		wait_for_upload_ready();
		assert (ioctl_din == 16'he718) else
			$fatal(1, "NVRAM_UPLOAD_DATA1 got=%04x", ioctl_din);

		@(negedge clk);
		ioctl_upload = 1'b0;
		ioctl_index = 16'h0000;
		#1;
		assert (!runtime_hold && !ioctl_wait && !memory_access && !memory_write)
			else $fatal(1, "NVRAM_IDLE_OUTPUTS");
		$display("NVRAM_IO_PASS prefetch_cycles=4 dirty_and_transfer=ok");
		$finish;
	end
endmodule
