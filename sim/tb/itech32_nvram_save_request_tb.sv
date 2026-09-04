`timescale 1ns/1ps

module itech32_nvram_save_request_tb;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic dirty = 1'b0;
	logic osd_status = 1'b0;
	logic upload_req;
	integer pulses = 0;

	itech32_nvram_save_request dut (
		.clk(clk), .reset(reset), .dirty(dirty),
		.osd_status(osd_status), .upload_req(upload_req)
	);

	always #5 clk = ~clk;
	always_ff @(posedge clk)
		if (upload_req)
			pulses <= pulses + 1;

	task automatic step_clock;
		@(negedge clk);
	endtask

	initial begin
		repeat (3) step_clock();
		reset = 1'b0;

		// Clean stores never request an upload.
		osd_status = 1'b1;
		repeat (3) step_clock();
		assert (!upload_req && pulses == 0) else
			$fatal(1, "NVRAM_CLEAN_OPEN_REQUESTED");
		osd_status = 1'b0;
		repeat (2) step_clock();

		// A dirty store produces exactly one pulse on the opening edge.
		dirty = 1'b1;
		osd_status = 1'b1;
		step_clock();
		assert (upload_req) else $fatal(1, "NVRAM_DIRTY_OPEN_MISSED");
		step_clock();
		assert (!upload_req) else $fatal(1, "NVRAM_OPEN_PULSE_TOO_LONG");

		// Upload start clears dirty; active work RAM can dirty again before the
		// OSD closes.  Neither transition may start a repeated-save loop.
		dirty = 1'b0;
		repeat (2) step_clock();
		dirty = 1'b1;
		repeat (4) step_clock();
		assert (!upload_req && pulses == 1) else
			$fatal(1, "NVRAM_RETRIGGERED_WHILE_OSD_OPEN pulses=%0d", pulses);

		// Closing and reopening arms the next intentional save.
		osd_status = 1'b0;
		repeat (2) step_clock();
		osd_status = 1'b1;
		step_clock();
		assert (upload_req) else $fatal(1, "NVRAM_SECOND_OPEN_MISSED");
		step_clock();
		assert (!upload_req && pulses == 2) else
			$fatal(1, "NVRAM_SECOND_OPEN_COUNT pulses=%0d", pulses);

		$display("NVRAM_SAVE_REQUEST_PASS one_pulse_per_osd_open=ok");
		$finish;
	end
endmodule
