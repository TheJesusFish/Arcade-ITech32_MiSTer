`timescale 1ns/1ps

module itech32_rle_prefetch_tb;
	localparam logic [25:0] GROM_BASE = 26'h0000100;
	localparam integer EXPECTED_WRITES = 20;

	logic clk = 1'b0;
	logic reset = 1'b1;
	logic reg_req = 1'b0;
	logic reg_we = 1'b0;
	logic [6:0] reg_addr = 7'd0;
	logic [15:0] reg_wdata = 16'd0;
	logic [1:0] reg_be = 2'b11;
	logic reg_ack;
	logic [15:0] reg_rdata;
	logic color0_we = 1'b0;
	logic color1_we = 1'b0;
	logic [7:0] color_data = 8'd0;
	logic scanline_event = 1'b0;
	logic irq_blitter;
	logic irq_scanline;
	logic [15:0] interrupt_state;
	logic busy;
	logic [15:0] timing_int_scanline;
	logic [15:0] timing_vtotal;
	logic [15:0] timing_vsync;
	logic [15:0] timing_vblank_start;
	logic [15:0] timing_vblank_end;
	logic [15:0] timing_htotal;
	logic [15:0] timing_hsync;
	logic [15:0] timing_hblank_start;
	logic [15:0] timing_hblank_end;
	logic [15:0] display_xorigin1;
	logic [15:0] display_yorigin1;
	logic [15:0] display_xorigin2;
	logic [15:0] display_yorigin2;
	logic [15:0] display_xscroll2;
	logic [15:0] display_yscroll2;
	logic grom_req;
	logic [25:0] grom_addr;
	logic grom_ack = 1'b0;
	logic [63:0] grom_rdata;
	logic vram_req;
	logic vram_we;
	logic vram_plane;
	logic [18:0] vram_addr;
	logic [15:0] vram_wdata;
	logic vram_ack = 1'b0;

	logic [7:0] grom_mem [0:63];
	logic grom_pending = 1'b0;
	logic [25:0] grom_saved_addr = 26'd0;
	integer grom_delay = 0;
	integer grom_requests = 0;
	logic early_next_request = 1'b0;
	logic delayed_boundary_seen = 1'b0;
	logic coincident_boundary_seen = 1'b0;
	logic speculative_drain_seen = 1'b0;
	integer second_qword_delay = 24;
	bit require_coincident = 1'b0;
	bit probe_only = 1'b0;
	bit debug_protocol = 1'b0;

	logic vram_pending = 1'b0;
	logic vram_saved_we = 1'b0;
	logic vram_saved_plane = 1'b0;
	logic [18:0] vram_saved_addr = 19'd0;
	logic [15:0] vram_saved_wdata = 16'd0;
	integer vram_delay = 0;
	integer accepted_writes = 0;
	integer cycles = 0;

	always #5 clk = ~clk;

	always_comb begin
		grom_rdata = 64'd0;
		for (integer byte_index = 0; byte_index < 8; byte_index++) begin
			if ({grom_saved_addr[25:3],3'b000} + 26'(byte_index) >= GROM_BASE &&
				{grom_saved_addr[25:3],3'b000} + 26'(byte_index) < GROM_BASE + 26'd64)
				grom_rdata[byte_index * 8 +: 8] =
					grom_mem[({grom_saved_addr[25:3],3'b000} +
						26'(byte_index)) - GROM_BASE];
		end
	end

	itech32_blitter dut (
		.clk(clk), .reset(reset), .timekill_mode(1'b0),
		.reg_req(reg_req), .reg_we(reg_we), .reg_addr(reg_addr),
		.reg_wdata(reg_wdata), .reg_be(reg_be), .reg_ack(reg_ack),
		.reg_rdata(reg_rdata), .color0_we(color0_we),
		.color1_we(color1_we), .color_data(color_data),
		.plane_enable(2'b01), .grom_bank(2'b00),
		.scanline_event(scanline_event), .irq_blitter(irq_blitter),
		.irq_scanline(irq_scanline), .interrupt_state(interrupt_state),
		.busy(busy), .timing_int_scanline(timing_int_scanline),
		.timing_vtotal(timing_vtotal), .timing_vsync(timing_vsync),
		.timing_vblank_start(timing_vblank_start),
		.timing_vblank_end(timing_vblank_end), .timing_htotal(timing_htotal),
		.timing_hsync(timing_hsync), .timing_hblank_start(timing_hblank_start),
		.timing_hblank_end(timing_hblank_end), .display_xorigin1(display_xorigin1),
		.display_yorigin1(display_yorigin1), .display_xorigin2(display_xorigin2),
		.display_yorigin2(display_yorigin2), .display_xscroll2(display_xscroll2),
		.display_yscroll2(display_yscroll2), .grom_req(grom_req),
		.grom_addr(grom_addr), .grom_ack(grom_ack), .grom_rdata(grom_rdata),
		.vram_req(vram_req), .vram_we(vram_we), .vram_plane(vram_plane),
		.vram_addr(vram_addr), .vram_wdata(vram_wdata), .vram_ack(vram_ack),
		.vram_rdata(16'h00ff), .vram_writes_pending(1'b0)
	);

	// Deliberately delay the second qword until after the parser reaches its
	// boundary.  A correct prefetch keeps the held address stable, reclassifies
	// that response as current, and resumes without skipping or duplicating data.
	always @(negedge clk) begin
		grom_ack = 1'b0;
		if (reset) begin
			grom_pending = 1'b0;
			grom_requests = 0;
			early_next_request = 1'b0;
			delayed_boundary_seen = 1'b0;
			coincident_boundary_seen = 1'b0;
			speculative_drain_seen = 1'b0;
		end else if (!grom_pending && grom_req) begin
			if (debug_protocol)
				$display("GROM_REQ cycle=%0d index=%0d addr=%07x ptr=%07x cur=%0d next=%0d role=%0d",
					cycles,grom_requests,grom_addr,dut.rle_pointer,
					dut.rle_qword_valid,dut.rle_next_qword_valid,dut.rle_fetch_next);
			if (grom_addr !== GROM_BASE + 26'(grom_requests * 8))
				$fatal(1,"non-sequential GROM request %0d addr=%07x",grom_requests,grom_addr);
			grom_saved_addr = grom_addr;
			grom_pending = 1'b1;
			if (grom_requests == 1) begin
				grom_delay = second_qword_delay;
				if (dut.rle_qword_valid && dut.rle_pointer[25:3] == GROM_BASE[25:3])
					early_next_request = 1'b1;
			end else if (grom_requests == 3) begin
				// Leave the sole unused look-ahead request outstanding so the
				// terminator must hold it through ACK before completion.
				grom_delay = 24;
			end else begin
				grom_delay = 1;
			end
			grom_requests = grom_requests + 1;
		end else if (grom_pending) begin
			if (!grom_req) begin
				$fatal(1,"GROM request withdrawn before ACK");
			end else begin
				if (grom_addr !== grom_saved_addr)
					$fatal(1,"GROM payload changed before ACK old=%07x new=%07x",
						grom_saved_addr,grom_addr);
				if (!dut.rle_qword_valid && dut.rle_pointer[25:3] == grom_saved_addr[25:3])
					delayed_boundary_seen = 1'b1;
				if (grom_requests == 4 && dut.state == dut.ST_RLE_FETCH_DRAIN)
					speculative_drain_seen = 1'b1;
				if (grom_delay == 0) begin
					if (dut.rle_boundary_consumed && dut.rle_fetch_next)
						coincident_boundary_seen = 1'b1;
					grom_ack = 1'b1;
					if (debug_protocol)
						$display("GROM_ACK cycle=%0d addr=%07x ptr=%07x boundary=%0d role=%0d",
							cycles,grom_addr,dut.rle_pointer,
							dut.rle_boundary_consumed,dut.rle_fetch_next);
					grom_pending = 1'b0;
				end else begin
					grom_delay = grom_delay - 1;
				end
			end
		end
	end

	// Add deterministic destination backpressure and check stability through it.
	always @(negedge clk) begin
		vram_ack = 1'b0;
		if (reset) begin
			vram_pending = 1'b0;
		end else if (!vram_pending && vram_req) begin
			vram_saved_we = vram_we;
			vram_saved_plane = vram_plane;
			vram_saved_addr = vram_addr;
			vram_saved_wdata = vram_wdata;
			vram_delay = accepted_writes % 4;
			vram_pending = 1'b1;
		end else if (vram_pending) begin
			if (!vram_req || vram_we !== vram_saved_we ||
				vram_plane !== vram_saved_plane || vram_addr !== vram_saved_addr ||
				vram_wdata !== vram_saved_wdata)
				$fatal(1,"VRAM payload changed while stalled");
			if (vram_delay == 0) begin
				vram_ack = 1'b1;
				vram_pending = 1'b0;
			end else begin
				vram_delay = vram_delay - 1;
			end
		end
	end

	always @(posedge clk) begin
		if (!reset) begin
			cycles <= cycles + 1;
			if (debug_protocol && (cycles % 100) == 0)
				$display("TRACE cycle=%0d state=%0d ptr=%07x row=%0d col=%0d count=%0d cur=%0d next=%0d fetch=%0d role=%0d out=%0d writes=%0d",
					cycles,dut.state,dut.rle_pointer,dut.rle_row,dut.rle_col,
					dut.rle_count,dut.rle_qword_valid,dut.rle_next_qword_valid,
					dut.rle_fetch_valid,dut.rle_fetch_next,dut.rle_output_valid,
					accepted_writes);
			if (cycles > 10000)
				$fatal(1,"RLE prefetch timeout state=%0d writes=%0d requests=%0d",
					dut.state,accepted_writes,grom_requests);
			if (vram_ack) begin
				if (!vram_req || !vram_we || vram_plane != 1'b0)
					$fatal(1,"unexpected VRAM transaction");
				if (accepted_writes >= EXPECTED_WRITES)
					$fatal(1,"extra VRAM write");
				if (vram_addr !== 19'(accepted_writes) ||
					vram_wdata !== {8'h00,8'(accepted_writes + 1)})
					$fatal(1,"write %0d mismatch addr=%05x data=%04x",
						accepted_writes,vram_addr,vram_wdata);
				accepted_writes <= accepted_writes + 1;
			end
		end
	end

	task automatic reg_write(input logic [6:0] address,input logic [15:0] value);
		integer timeout;
		begin
			@(negedge clk);
			reg_addr = address;
			reg_wdata = value;
			reg_we = 1'b1;
			reg_req = 1'b1;
			timeout = 0;
			do begin
				@(posedge clk); #1;
				timeout = timeout + 1;
				if (timeout > 1000) $fatal(1,"register timeout addr=%02x",address);
			end while (!reg_ack);
			@(negedge clk);
			reg_req = 1'b0;
			reg_we = 1'b0;
		end
	endtask

	initial begin
		void'($value$plusargs("SECOND_DELAY=%d",second_qword_delay));
		require_coincident = $test$plusargs("REQUIRE_COINCIDENT");
		probe_only = $test$plusargs("PROBE_ONLY");
		debug_protocol = $test$plusargs("DEBUG_PROTOCOL");
		for (integer index = 0; index < 64; index++) grom_mem[index] = 8'h00;
		grom_mem[0] = 8'h94; // literal run, 20 pixels
		for (integer index = 0; index < EXPECTED_WRITES; index++)
			grom_mem[index + 1] = 8'(index + 1);
		grom_mem[21] = 8'h00; // command terminator before the declared row width

		repeat (4) @(posedge clk);
		@(negedge clk);
		reset = 1'b0;
		repeat (2) @(posedge clk);
		reg_write(7'h03,16'h0000);
		reg_write(7'h07,16'd30);
		reg_write(7'h06,16'd1);
		reg_write(7'h09,16'd0);
		reg_write(7'h0a,16'd0);
		reg_write(7'h17,{8'd0,GROM_BASE[23:16]});
		reg_write(7'h08,GROM_BASE[15:0]);
		reg_write(7'h0e,16'h0100);
		reg_write(7'h04,16'd2);
		while (busy || grom_pending || vram_pending || vram_req) @(posedge clk);
		repeat (4) @(posedge clk);

		if (accepted_writes != EXPECTED_WRITES)
			$fatal(1,"short write stream got=%0d expected=%0d",accepted_writes,EXPECTED_WRITES);
		if (!early_next_request)
			$fatal(1,"next qword was not requested while current qword remained resident");
		if (!probe_only && require_coincident && !coincident_boundary_seen)
			$fatal(1,"next-qword ACK did not coincide with byte-seven retirement");
		if (!probe_only && !require_coincident && !delayed_boundary_seen)
			$fatal(1,"delayed next-qword demand boundary was not exercised");
		if (!probe_only && !speculative_drain_seen)
			$fatal(1,"terminator did not drain the unused look-ahead request");
		if (grom_requests < 3 || grom_requests > 4)
			$fatal(1,"physical request count outside demand plus one: %0d",grom_requests);
		$display("PASS: RLE next-qword prefetch writes=%0d requests=%0d delayed=%0d coincident=%0d drain=%0d second_delay=%0d cycles=%0d",
			accepted_writes,grom_requests,delayed_boundary_seen,
			coincident_boundary_seen,speculative_drain_seen,second_qword_delay,cycles);
		$finish;
	end
endmodule
