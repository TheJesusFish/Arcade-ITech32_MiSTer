`timescale 1ns/1ps

module itech32_blitter_tb;
	localparam integer VRAM_WORDS = 512 * 1024;
	localparam integer GROM_BYTES = 4096;
	// Keep this focused white-box check aligned with the production enum order.
	localparam logic [3:0] BLITTER_WAIT_DRAIN_STATE = 4'd13;

	logic clk = 0;
	logic reset = 1;
	logic timekill_mode = 1'b0;
	logic reg_req, reg_we;
	logic [6:0] reg_addr;
	logic [15:0] reg_wdata;
	logic [1:0] reg_be;
	logic reg_ack;
	logic [15:0] reg_rdata;
	logic color0_we, color1_we;
	logic [7:0] color_data;
	logic [1:0] plane_enable;
	logic [1:0] grom_bank;
	logic scanline_event;
	logic irq_blitter, irq_scanline;
	logic [15:0] interrupt_state;
	logic busy;
	logic [15:0] timing_int_scanline, timing_vtotal, timing_vsync;
	logic [15:0] timing_vblank_start, timing_vblank_end;
	logic [15:0] timing_htotal, timing_hsync, timing_hblank_start, timing_hblank_end;
	logic [15:0] display_xorigin1, display_yorigin1;
	logic [15:0] display_xorigin2, display_yorigin2;
	logic [15:0] display_xscroll2, display_yscroll2;
	logic grom_req, grom_ack;
	logic [25:0] grom_addr;
	logic [63:0] grom_rdata;
	logic vram_req, vram_we, vram_plane, vram_ack;
	logic [18:0] vram_addr;
	logic [15:0] vram_wdata, vram_rdata;
	logic vram_writes_pending;

	logic [7:0] grom_mem [0:GROM_BYTES-1];
	logic [15:0] vram_mem [0:1][0:VRAM_WORDS-1];
	logic [15:0] expected [0:VRAM_WORDS-1];
	logic [15:0] shift_source [0:511];

	logic grom_pending;
	logic [25:0] grom_saved_addr;
	logic [2:0] grom_delay;
	logic vram_pending;
	logic vram_saved_we, vram_saved_plane;
	logic [18:0] vram_saved_addr;
	logic [15:0] vram_saved_wdata;
	logic [2:0] vram_delay;
	logic [31:0] lfsr;
	logic random_stalls;
	logic vram_immediate_ack;

	integer i;
	integer j;
	integer failures = 0;
	integer tests = 0;
	integer last_write_ack_cycles = 0;
	integer vram_read_acks = 0;
	integer vram_write_acks = 0;
	integer shift_reads_at_first_write = -1;
	integer shift_max_ready_gap = 0;
	integer shift_last_write_cycle = -1;
	integer simulation_cycle = 0;
	integer shift_plane_reads [0:1];
	integer shift_plane_writes [0:1];
	logic shift_monitor_enable = 1'b0;
	integer done_pulses = 0;
	logic [15:0] got;

	always #5 clk = ~clk;

	assign grom_ack = grom_pending && (grom_delay == 0);
	always_comb begin
		for (int byte_index = 0; byte_index < 8; byte_index++)
			grom_rdata[byte_index * 8 +: 8] =
				grom_mem[{grom_saved_addr[11:3], 3'b000} + byte_index];
	end
	assign vram_ack = vram_immediate_ack ? vram_req :
		(vram_pending && (vram_delay == 0));
	assign vram_rdata = vram_immediate_ack ? vram_mem[vram_plane][vram_addr] :
		vram_mem[vram_saved_plane][vram_saved_addr];

	itech32_blitter dut (
		.clk(clk), .reset(reset), .timekill_mode(timekill_mode),
		.reg_req(reg_req), .reg_we(reg_we), .reg_addr(reg_addr),
		.reg_wdata(reg_wdata), .reg_be(reg_be), .reg_ack(reg_ack), .reg_rdata(reg_rdata),
		.color0_we(color0_we), .color1_we(color1_we), .color_data(color_data),
		.plane_enable(plane_enable), .grom_bank(grom_bank),
		.scanline_event(scanline_event), .irq_blitter(irq_blitter),
		.irq_scanline(irq_scanline), .interrupt_state(interrupt_state), .busy(busy),
		.timing_int_scanline(timing_int_scanline), .timing_vtotal(timing_vtotal), .timing_vsync(timing_vsync),
		.timing_vblank_start(timing_vblank_start), .timing_vblank_end(timing_vblank_end),
		.timing_htotal(timing_htotal), .timing_hsync(timing_hsync),
		.timing_hblank_start(timing_hblank_start), .timing_hblank_end(timing_hblank_end),
		.display_xorigin1(display_xorigin1), .display_yorigin1(display_yorigin1),
		.display_xorigin2(display_xorigin2), .display_yorigin2(display_yorigin2),
		.display_xscroll2(display_xscroll2), .display_yscroll2(display_yscroll2),
		.grom_req(grom_req), .grom_addr(grom_addr), .grom_ack(grom_ack), .grom_rdata(grom_rdata),
		.vram_req(vram_req), .vram_we(vram_we), .vram_plane(vram_plane),
		.vram_addr(vram_addr), .vram_wdata(vram_wdata), .vram_ack(vram_ack),
		.vram_rdata(vram_rdata), .vram_writes_pending(vram_writes_pending)
	);

	function automatic logic [18:0] va(input integer x, input integer y);
		va = {y[9:0], x[8:0]};
	endfunction

	always_ff @(posedge clk) begin
		logic accepted_vram_we;
		logic accepted_vram_plane;
		logic [18:0] accepted_vram_addr;
		logic [15:0] accepted_vram_wdata;

		accepted_vram_we = vram_immediate_ack ? vram_we : vram_saved_we;
		accepted_vram_plane = vram_immediate_ack ? vram_plane : vram_saved_plane;
		accepted_vram_addr = vram_immediate_ack ? vram_addr : vram_saved_addr;
		accepted_vram_wdata = vram_immediate_ack ? vram_wdata : vram_saved_wdata;

		if (reset) begin
			grom_pending <= 1'b0;
			vram_pending <= 1'b0;
			vram_read_acks <= 0;
			vram_write_acks <= 0;
			shift_reads_at_first_write <= -1;
			shift_max_ready_gap <= 0;
			shift_last_write_cycle <= -1;
			simulation_cycle <= 0;
			shift_plane_reads[0] <= 0;
			shift_plane_reads[1] <= 0;
			shift_plane_writes[0] <= 0;
			shift_plane_writes[1] <= 0;
			done_pulses <= 0;
			grom_delay <= 0;
			vram_delay <= 0;
			lfsr <= 32'h1ace_b00c;
		end else begin
			simulation_cycle <= simulation_cycle + 1;
			if (dut.blitter_done_pulse)
				done_pulses <= done_pulses + 1;
			if (vram_ack) begin
				if (accepted_vram_we) begin
					vram_write_acks <= vram_write_acks + 1;
					if (shift_monitor_enable && dut.state == 4'd14) begin
						assert (shift_plane_reads[accepted_vram_plane] == 512)
							else $fatal(1, "shift write before plane %0d fill reads=%0d",
								accepted_vram_plane, shift_plane_reads[accepted_vram_plane]);
						shift_plane_writes[accepted_vram_plane] <=
							shift_plane_writes[accepted_vram_plane] + 1;
						if (shift_reads_at_first_write < 0)
							shift_reads_at_first_write <= vram_read_acks;
						if (shift_last_write_cycle >= 0 &&
							dut.shift_output_word != 9'd0 &&
							(simulation_cycle - shift_last_write_cycle) > shift_max_ready_gap)
							shift_max_ready_gap <= simulation_cycle - shift_last_write_cycle;
						shift_last_write_cycle <= simulation_cycle;
					end
				end else begin
					vram_read_acks <= vram_read_acks + 1;
					if (shift_monitor_enable && dut.state == 4'd9)
						shift_plane_reads[accepted_vram_plane] <=
							shift_plane_reads[accepted_vram_plane] + 1;
				end
			end
			lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};

			if (!grom_pending && grom_req) begin
				if (grom_addr >= GROM_BYTES) $fatal(1, "GROM address outside test memory: %x", grom_addr);
				grom_pending <= 1'b1;
				grom_saved_addr <= grom_addr;
				grom_delay <= random_stalls ? {1'b0, lfsr[1:0]} : 3'd0;
			end else if (grom_pending) begin
				if (!grom_req || grom_addr != grom_saved_addr)
					$fatal(1, "GROM request changed while stalled");
				if (grom_delay != 0)
					grom_delay <= grom_delay - 1'b1;
				else
					grom_pending <= 1'b0;
			end

			if (vram_immediate_ack) begin
				vram_pending <= 1'b0;
				if (vram_req && vram_we)
					vram_mem[accepted_vram_plane][accepted_vram_addr] <=
						accepted_vram_wdata;
			end else begin
				if (!vram_pending && vram_req) begin
					vram_pending <= 1'b1;
					vram_saved_we <= vram_we;
					vram_saved_plane <= vram_plane;
					vram_saved_addr <= vram_addr;
					vram_saved_wdata <= vram_wdata;
					vram_delay <= random_stalls ? {1'b0, lfsr[3:2]} : 3'd0;
				end else if (vram_pending) begin
					if (!vram_req || vram_we != vram_saved_we || vram_plane != vram_saved_plane ||
						vram_addr != vram_saved_addr || (vram_saved_we && vram_wdata != vram_saved_wdata))
						$fatal(1, "VRAM request changed while stalled");
					if (vram_delay != 0) begin
						vram_delay <= vram_delay - 1'b1;
					end else begin
						if (vram_saved_we)
							vram_mem[vram_saved_plane][vram_saved_addr] <= vram_saved_wdata;
						vram_pending <= 1'b0;
					end
				end
			end
		end
	end

	task automatic pulse_reset;
		begin
			@(negedge clk);
			reset = 1;
			reg_req = 0;
			color0_we = 0;
			color1_we = 0;
			scanline_event = 0;
			vram_writes_pending = 0;
			repeat (3) @(posedge clk);
			@(negedge clk);
			reset = 0;
			repeat (2) @(posedge clk);
		end
	endtask

	task automatic reg_write_be(
		input logic [6:0] address,
		input logic [15:0] value,
		input logic [1:0] byte_enable
	);
		integer timeout;
		begin
			@(negedge clk);
			reg_addr = address;
			reg_wdata = value;
			reg_be = byte_enable;
			reg_we = 1;
			reg_req = 1;
			timeout = 0;
			do begin
				@(posedge clk); #1;
				timeout = timeout + 1;
				if (timeout > 2000000) $fatal(1, "register write timeout addr=%x", address);
			end while (!reg_ack);
			last_write_ack_cycles = timeout;
			@(negedge clk);
			reg_req = 0;
			reg_we = 0;
		end
	endtask

	task automatic reg_write(input logic [6:0] address, input logic [15:0] value);
		begin
			reg_write_be(address, value, 2'b11);
		end
	endtask

	task automatic reg_read(input logic [6:0] address, output logic [15:0] value);
		integer timeout;
		begin
			@(negedge clk);
			reg_addr = address;
			reg_wdata = 0;
			reg_be = 2'b11;
			reg_we = 0;
			reg_req = 1;
			timeout = 0;
			do begin
				@(posedge clk); #1;
				timeout = timeout + 1;
				if (timeout > 1000) $fatal(1, "register read timeout addr=%x", address);
			end while (!reg_ack);
			value = reg_rdata;
			@(negedge clk);
			reg_req = 0;
		end
	endtask

	task automatic set_color(input logic [7:0] value);
		begin
			@(negedge clk);
			color_data = value;
			color0_we = 1;
			@(posedge clk);
			@(negedge clk);
			color0_we = 0;
		end
	endtask

	task automatic wait_idle;
		integer timeout;
		begin
			timeout = 0;
			while (busy || grom_pending || vram_pending) begin
				@(posedge clk);
				timeout = timeout + 1;
				if (timeout > 4000000) $fatal(1, "blitter timeout state=%0d", dut.state);
			end
			repeat (3) @(posedge clk);
		end
	endtask

	task automatic clear_mem(input logic [15:0] value);
		begin
			for (i = 0; i < VRAM_WORDS; i = i + 1) begin
				vram_mem[0][i] = value;
				vram_mem[1][i] = value;
				expected[i] = value;
			end
			for (i = 0; i < GROM_BYTES; i = i + 1)
				grom_mem[i] = 0;
		end
	endtask

	task automatic expect_all(input string name);
		integer mismatches;
		begin
			mismatches = 0;
			for (i = 0; i < VRAM_WORDS; i = i + 1) begin
				if (vram_mem[0][i] !== expected[i]) begin
					if (mismatches < 8)
						$display("%s mismatch addr=%05x got=%04x expected=%04x", name, i, vram_mem[0][i], expected[i]);
					mismatches = mismatches + 1;
				end
			end
			if (mismatches != 0) begin
				failures = failures + 1;
				$display("FAIL %s (%0d mismatches)", name, mismatches);
			end else begin
				$display("PASS %s", name);
			end
			tests = tests + 1;
		end
	endtask

	task automatic expect_value(input logic condition, input string name);
		begin
			tests = tests + 1;
			if (!condition) begin
				failures = failures + 1;
				$display("FAIL %s", name);
			end else begin
				$display("PASS %s", name);
			end
		end
	endtask

	task automatic configure(
		input logic [15:0] flags,
		input logic [15:0] width,
		input logic [15:0] height,
		input logic [15:0] x,
		input logic [15:0] y
	);
		begin
			reg_write(7'h03, flags);
			reg_write(7'h06, height);
			reg_write(7'h07, width);
			reg_write(7'h08, 16'd0);
			reg_write(7'h17, 16'd0);
			reg_write(7'h09, x);
			reg_write(7'h0a, y);
			reg_write(7'h0b, 16'h0100);
			reg_write(7'h0c, 16'h0100);
			reg_write(7'h0d, 16'h0100);
			reg_write(7'h0e, 16'h0100);
			reg_write(7'h0f, 16'd0);
			reg_write(7'h10, 16'd0);
			reg_write(7'h12, 16'd0);
			reg_write(7'h13, 16'd512);
			reg_write(7'h14, 16'd0);
			reg_write(7'h15, 16'd1024);
		end
	endtask

	initial begin
		reg_req = 0;
		reg_we = 0;
		reg_addr = 0;
		reg_wdata = 0;
		reg_be = 0;
		color0_we = 0;
		color1_we = 0;
		color_data = 0;
		plane_enable = 2'b01;
		grom_bank = 0;
		scanline_event = 0;
		random_stalls = 1;
		vram_immediate_ack = 0;
		vram_writes_pending = 0;
		clear_mem(16'hdead);
		pulse_reset();

		// V0: height packing and masked address arithmetic.
		expect_value(dut.adjusted_height(16'h0000) == 9'h000, "V0 height 0000");
		expect_value(dut.adjusted_height(16'h0001) == 9'h001, "V0 height 0001");
		expect_value(dut.adjusted_height(16'h00ff) == 9'h0ff, "V0 height 00ff");
		expect_value(dut.adjusted_height(16'h0100) == 9'h000, "V0 ignored bit 8");
		expect_value(dut.adjusted_height(16'h0200) == 9'h100, "V0 packed bit 9");
		expect_value(dut.adjusted_height(16'h02ff) == 9'h1ff, "V0 maximum height");
		expect_value(va(12'h200,12'h400) == 19'h00000, "V0 address wrap zero");
		expect_value(va(12'h3ff,12'h7ff) == 19'h7ffff, "V0 address masks");

		// Time Killers uses 512-row planes and different color-latch packing.
		timekill_mode = 1'b1;
		expect_value(dut.integer_vram_address(12'h123, 12'h3ff) ==
			{1'b0, 9'h1ff, 9'h123}, "TK integer VRAM 512-row mask");
		expect_value(dut.fixed_vram_address(32'sh00012300, 32'sh0003ff00) ==
			{1'b0, 9'h1ff, 9'h123}, "TK fixed VRAM 512-row mask");
		set_color(8'hab);
		expect_value(dut.color_latch[0] == 16'h0b00,
			"TK color A low-nibble latch");
		@(negedge clk); color_data=8'hc5; color1_we=1'b1;
		@(posedge clk); #1;
		@(negedge clk); color1_we=1'b0;
		expect_value(dut.color_latch[1] == 16'h1c00,
			"TK color BC high-nibble latch");
		timekill_mode = 1'b0;
		pulse_reset();

		// Exercise both banks implicated by the routed 128-way write-select path.
		// General writes retain their original capture/execute (two-edge) ACK and
		// merge each enabled byte without aliasing another one-hot destination.
		reg_write(7'h3f, 16'ha55a);
		expect_value(last_write_ack_cycles == 2, "V0 general register ACK latency");
		reg_write(7'h76, 16'h3cc3);
		reg_write_be(7'h3f, 16'h12e7, 2'b01);
		expect_value(last_write_ack_cycles == 2, "V0 byte write ACK latency");
		reg_write_be(7'h76, 16'h8104, 2'b10);
		reg_read(7'h3f, got);
		expect_value(got == 16'ha5e7, "V0 one-hot low-byte merge");
		reg_read(7'h76, got);
		expect_value(got == 16'h81c3, "V0 one-hot high-byte merge/no alias");

		// V1: raw rows, color and transparency.
		clear_mem(16'hdead); pulse_reset(); set_color(8'h12);
		grom_mem[0]=8'h01; grom_mem[1]=8'hff; grom_mem[2]=8'h03; grom_mem[3]=8'h04;
		grom_mem[4]=8'h05; grom_mem[5]=8'h06; grom_mem[6]=8'hff; grom_mem[7]=8'h08;
		configure(16'h0401,4,2,10,20);
		reg_write(7'h04,1); wait_idle();
		expected[va(10,20)]=16'h1201; expected[va(12,20)]=16'h1203; expected[va(13,20)]=16'h1204;
		expected[va(10,21)]=16'h1205; expected[va(11,21)]=16'h1206; expected[va(13,21)]=16'h1208;
		expect_all("V1 raw transparency");

		// V2: raw destination scaling, both flips and strict clipping.
		clear_mem(16'hdead); pulse_reset(); set_color(8'h20);
		for (i=0;i<8;i=i+1) grom_mem[i]=i+1;
		configure(16'h040e,4,2,8,7);
		reg_write(7'h0d,16'h0180);
		reg_write(7'h12,4); reg_write(7'h13,8); reg_write(7'h14,6); reg_write(7'h15,8);
		reg_write(7'h04,1); wait_idle();
		expected[va(6,7)]=16'h2002; expected[va(5,7)]=16'h2003;
		expected[va(6,6)]=16'h2006; expected[va(5,6)]=16'h2007;
		expect_all("V2 raw scale flip clip");

		// V3a: ordinary raw source step duplicates source samples.
		clear_mem(16'hdead); pulse_reset(); set_color(8'h12);
		grom_mem[0]=8'h11; grom_mem[1]=8'h22; grom_mem[2]=8'h33; grom_mem[3]=8'h44;
		configure(16'h0400,4,1,10,20); reg_write(7'h0c,16'h0080);
		reg_write(7'h04,1); wait_idle();
		expected[va(10,20)]=16'h1211; expected[va(11,20)]=16'h1211;
		expected[va(12,20)]=16'h1222; expected[va(13,20)]=16'h1222;
		expected[va(14,20)]=16'h1233; expected[va(15,20)]=16'h1233;
		expected[va(16,20)]=16'h1244; expected[va(17,20)]=16'h1244;
		expect_all("V3a raw source scaling");

		// V3b: WIDTHPIX performs exactly WIDTH iterations.
		clear_mem(16'hdead); pulse_reset(); set_color(8'h12);
		grom_mem[0]=8'h11; grom_mem[1]=8'h22; grom_mem[2]=8'h33; grom_mem[3]=8'h44;
		configure(16'h8400,4,1,10,21); reg_write(7'h0c,16'h0080);
		reg_write(7'h04,1); wait_idle();
		expected[va(10,21)]=16'h1211; expected[va(11,21)]=16'h1211;
		expected[va(12,21)]=16'h1222; expected[va(13,21)]=16'h1222;
		expect_all("V3b WIDTHPIX");

		// V4: signed raw Y-per-X and X-per-Y skew.
		clear_mem(16'hdead); pulse_reset(); set_color(8'h12);
		for (i=0;i<6;i=i+1) grom_mem[i]=i+1;
		configure(16'h0430,3,2,10,10);
		reg_write(7'h0f,16'h0080); reg_write(7'h10,16'h0100);
		reg_write(7'h04,1); wait_idle();
		expected[va(10,10)]=16'h1201; expected[va(11,9)]=16'h1202; expected[va(12,9)]=16'h1203;
		expected[va(11,11)]=16'h1204; expected[va(12,10)]=16'h1205; expected[va(13,10)]=16'h1206;
		expect_all("V4 raw skew signs");

		// V5: RLE cross-row state plus horizontal clip skipping.
		clear_mem(16'hdead); pulse_reset(); set_color(8'h12);
		grom_mem[0]=8'h03; grom_mem[1]=8'ha1; grom_mem[2]=8'h84; grom_mem[3]=8'hff;
		grom_mem[4]=8'hb1; grom_mem[5]=8'hb3; grom_mem[6]=8'hb4; grom_mem[7]=8'h03; grom_mem[8]=8'hc1;
		configure(16'h0401,5,2,10,20);
		reg_write(7'h12,11); reg_write(7'h13,14); reg_write(7'h14,20); reg_write(7'h15,22);
		reg_write(7'h04,2); wait_idle();
		expected[va(11,20)]=16'h12a1; expected[va(12,20)]=16'h12a1;
		expected[va(11,21)]=16'h12b4; expected[va(12,21)]=16'h12c1; expected[va(13,21)]=16'h12c1;
		expect_all("V5 RLE carry clip transparency");

		// V6a: fast RLE X/Y flip and transparent repeat.
		clear_mem(16'hdead); pulse_reset(); set_color(8'h30);
		grom_mem[0]=8'h84; grom_mem[1]=1; grom_mem[2]=2; grom_mem[3]=3; grom_mem[4]=4;
		grom_mem[5]=8'h04; grom_mem[6]=8'hff;
		configure(16'h0407,4,2,20,30);
		reg_write(7'h04,2); wait_idle();
		expected[va(20,30)]=16'h3001; expected[va(19,30)]=16'h3002;
		expected[va(18,30)]=16'h3003; expected[va(17,30)]=16'h3004;
		expect_all("V6a RLE flips transparent repeat");

		// V6b: MAME's fast-X-flip interval is (left,right].
		clear_mem(16'hdead); pulse_reset(); set_color(8'h12);
		grom_mem[0]=8'h84; grom_mem[1]=1; grom_mem[2]=2; grom_mem[3]=3; grom_mem[4]=4;
		configure(16'h0402,4,1,20,30); reg_write(7'h12,17); reg_write(7'h13,20);
		reg_write(7'h04,2); wait_idle();
		expected[va(20,30)]=16'h1201; expected[va(19,30)]=16'h1202; expected[va(18,30)]=16'h1203;
		expect_all("V6b RLE flipped clip edges");

		// V7a: slow RLE scale/skew; YSTEP_PER_X is intentionally ignored.
		clear_mem(16'hdead); pulse_reset(); set_color(8'h40);
		grom_mem[0]=8'h88; for (i=1;i<=8;i=i+1) grom_mem[i]=i;
		configure(16'h0428,4,2,8,10);
		reg_write(7'h0d,16'h0180); reg_write(7'h0f,16'h0055); reg_write(7'h10,16'h0080);
		reg_write(7'h12,9); reg_write(7'h13,13); reg_write(7'h14,10); reg_write(7'h15,12);
		reg_write(7'h04,2); wait_idle();
		expected[va(9,10)]=16'h4002; expected[va(11,10)]=16'h4003; expected[va(12,10)]=16'h4004;
		expected[va(10,11)]=16'h4006; expected[va(11,11)]=16'h4007;
		expect_all("V7a slow RLE scale skew");

		// V7b: downscale collision is later-source-wins.
		clear_mem(16'hdead); pulse_reset(); set_color(8'h12);
		grom_mem[0]=8'h84; grom_mem[1]=1; grom_mem[2]=2; grom_mem[3]=3; grom_mem[4]=4;
		configure(16'h0408,4,1,30,12); reg_write(7'h0d,16'h0080);
		reg_write(7'h04,2); wait_idle();
		expected[va(30,12)]=16'h1202; expected[va(31,12)]=16'h1204;
		expect_all("V7b RLE downscale overwrite");

		// V8: command-3 displaced reads, wrap and early completion IRQ.
		clear_mem(16'hdead); pulse_reset(); set_color(8'h12);
		vram_mem[0][va(511,100)]=16'h1111; expected[va(511,100)]=16'h1111;
		vram_mem[0][va(0,100)]=16'h2222; expected[va(0,100)]=16'h2222;
		vram_mem[0][va(511,101)]=16'h3333; expected[va(511,101)]=16'h3333;
		vram_mem[0][va(0,101)]=16'h4444; expected[va(0,101)]=16'h4444;
		configure(16'h0000,2,2,511,100); reg_write(7'h05,16'h0040); reg_write(7'h04,3);
		repeat (3) @(posedge clk);
		expect_value(interrupt_state[6] && irq_blitter, "V8 command 3 immediate done");
		reg_write(7'h01,16'h0040); repeat (3) @(posedge clk);
		reg_write(7'h02,16'h00a0); reg_read(7'h02,got); expect_value(got==16'h1111,"V8 displaced 1");
		reg_read(7'h02,got); expect_value(got==16'h1111,"V8 read does not advance");
		reg_write(7'h02,16'hf0a1); reg_read(7'h02,got); expect_value(got==16'h2222,"V8 displaced 2");
		reg_write(7'h02,16'h00b0); reg_read(7'h02,got); expect_value(got==16'h3333,"V8 displaced 3");
		reg_write(7'h02,16'h00b1); reg_read(7'h02,got); expect_value(got==16'h4444,"V8 displaced 4");
		repeat (3) @(posedge clk); expect_value(!interrupt_state[6],"V8 transfers do not reassert done");
		expected[va(511,100)]=16'h12a0; expected[va(0,100)]=16'h12a1;
		expected[va(511,101)]=16'h12b0; expected[va(0,101)]=16'h12b1;
		reg_write(7'h02,16'h55cc); reg_read(7'h02,got); expect_value(got==16'h55cc,"V8 post-stream transfer register");
		expect_all("V8 command 3 VRAM");

		// V9: command 6 copies a linear 512-word block upward from nonzero X.
		pulse_reset();
		for (i=0;i<VRAM_WORDS;i=i+1) begin
			vram_mem[0][i]=(i ^ 32'ha55a) & 16'hffff;
			vram_mem[1][i]=(i ^ 32'h5aa5) & 16'hffff;
			expected[i]=(i ^ 32'ha55a) & 16'hffff;
		end
		for (i=0;i<512;i=i+1) shift_source[i]=expected[va(510,40)+i];
		configure(16'h0404,1,3,510,40);
		reg_write(7'h12,100); reg_write(7'h13,101); reg_write(7'h14,100); reg_write(7'h15,101);
		shift_monitor_enable = 1'b1;
		reg_write(7'h04,6); wait_idle();
		shift_monitor_enable = 1'b0;
		for (i=0;i<512;i=i+1) begin
			expected[va(510,39)+i]=shift_source[i];
			expected[va(510,38)+i]=shift_source[i];
		end
		expect_value(vram_read_acks == 512, "V9 shift source fetched once");
		expect_value(vram_write_acks == 1024, "V9 shift writes both destination rows");
		expect_value(shift_reads_at_first_write == 512,
			"V9 full source fill precedes first destination write");
		expect_value(shift_max_ready_gap <= 5,
			"V9 replay does not add a per-word pipeline bubble");
		expect_all("V9 shift-register linear copy");

		// V9b: each enabled plane takes its own complete source snapshot before
		// any writes to that plane.  Distinct data catches accidental plane-0 M10K
		// reuse when replay transitions to plane 1.
		pulse_reset(); plane_enable = 2'b11;
		for (i=0;i<VRAM_WORDS;i=i+1) begin
			vram_mem[0][i]=16'h1000 + i[8:0];
			vram_mem[1][i]=16'h8000 + i[8:0];
			expected[i]=16'h1000 + i[8:0];
		end
		configure(16'h0400,1,2,0,80);
		shift_monitor_enable = 1'b1;
		reg_write(7'h04,6); wait_idle();
		shift_monitor_enable = 1'b0;
		for (i=0;i<512;i=i+1) begin
			expected[va(0,81)+i]=16'h1000 + i[8:0];
			if (vram_mem[1][va(0,81)+i] !== (16'h8000 + i[8:0]))
				$fatal(1,"V9b plane-1 source mismatch word=%0d got=%04x",
					i, vram_mem[1][va(0,81)+i]);
		end
		expect_value(vram_read_acks == 1024,
			"V9b exactly 512 source reads per enabled plane");
		expect_value(vram_write_acks == 1024,
			"V9b one replay row per enabled plane");
		expect_all("V9b independent two-plane source snapshots");
		plane_enable = 2'b01;

		// V9c: maximum-height, one-plane replay under an always-ready VRAM
		// sink.  Randomized ACK/hold behavior is covered by V9/V9b; this case
		// isolates the M10K replay pipeline and proves one accepted word per
		// fabric clock inside each row.  Only selected rows need data checking:
		// exact transaction counts catch missing or additional traffic.
		pulse_reset();
		for (i=0;i<512;i=i+1)
			vram_mem[0][va(0,300)+i] = 16'h4000 + i[8:0];
		for (j=1;j<256;j=j+1)
			for (i=0;i<512;i=i+1)
				vram_mem[0][va(0,300+j)+i] = 16'hdead;
		configure(16'h0400,1,16'h0200,0,300);
		vram_immediate_ack = 1'b1;
		shift_monitor_enable = 1'b1;
		reg_write(7'h04,6); wait_idle();
		shift_monitor_enable = 1'b0;
		vram_immediate_ack = 1'b0;
		expect_value(vram_read_acks == 512,
			"V9c maximum-height source fetched exactly once");
		expect_value(vram_write_acks == 130560,
			"V9c maximum-height emits exactly 130560 writes");
		expect_value(shift_reads_at_first_write == 512,
			"V9c no destination write precedes full source fill");
		expect_value(shift_max_ready_gap <= 1,
			"V9c always-ready replay accepts one word per clock");
		begin : check_v9c_selected_rows
			integer row_mismatches;
			row_mismatches = 0;
			for (i=0;i<512;i=i+1) begin
				if (vram_mem[0][va(0,301)+i] !== (16'h4000 + i[8:0]))
					row_mismatches = row_mismatches + 1;
				if (vram_mem[0][va(0,428)+i] !== (16'h4000 + i[8:0]))
					row_mismatches = row_mismatches + 1;
				if (vram_mem[0][va(0,555)+i] !== (16'h4000 + i[8:0]))
					row_mismatches = row_mismatches + 1;
			end
			expect_value(row_mismatches == 0,
				"V9c first/middle/last replay rows match source");
		end

		// V10: an ACKed final pixel may still be retained in the downstream
		// FIFO. Completion stays busy and command writes remain pending until the
		// accepted write sequence reaches the shared-memory boundary.
		clear_mem(16'hdead); pulse_reset(); set_color(8'h12);
		random_stalls = 0;
		grom_mem[0] = 8'h5a;
		configure(16'h0400,1,1,10,20);
		vram_writes_pending = 1;
		reg_write(7'h04,1);
		while (dut.state != BLITTER_WAIT_DRAIN_STATE)
			@(posedge clk);
		repeat (4) begin
			@(posedge clk); #1;
			if (!busy || interrupt_state[6] || dut.blitter_done_pulse)
				$fatal(1, "completion escaped retained-write tail");
		end
		// Present the next command while WAIT_DRAIN is busy. The ordinary
		// register capture stage may retain it, but it must not ACK or start.
		@(negedge clk);
		reg_addr = 7'h04;
		reg_wdata = 16'd1;
		reg_be = 2'b11;
		reg_we = 1;
		reg_req = 1;
		repeat (4) begin
			@(posedge clk); #1;
			if (reg_ack || !busy || interrupt_state[6])
				$fatal(1, "queued command advanced before retained writes drained");
		end
		expect_value(dut.reg_pending && dut.reg_command_write_q,
			"V10 next command retained behind drain");
		@(negedge clk);
		vram_writes_pending = 0;
		@(posedge clk); #1;
		expect_value(!busy && dut.blitter_done_pulse,
			"V10 drain releases first command completion");
		@(posedge clk); #1;
		expect_value(reg_ack && busy && dut.state == 4'd1,
			"V10 queued command starts after durable completion");
		expect_value(done_pulses == 1 && interrupt_state[6],
			"V10 exactly one durable done pulse before next command");
		@(negedge clk);
		reg_req = 0;
		reg_we = 0;
		wait_idle();
		random_stalls = 1;

		// V11: interrupt state/enable/W1C and read quirks.
		clear_mem(16'hdead); pulse_reset();
		reg_write(7'h05,0); reg_write(7'h04,4); repeat (3) @(posedge clk);
		expect_value(interrupt_state==16'h0040 && !irq_blitter,"V11 pending while masked");
		reg_write(7'h05,16'h0040); expect_value(irq_blitter,"V11 enable pending blitter");
		reg_write(7'h01,16'h0004); repeat (3) @(posedge clk); expect_value(interrupt_state==16'h0040,"V11 unrelated ACK");
		reg_write(7'h01,16'h0040); repeat (3) @(posedge clk); expect_value(interrupt_state==0 && !irq_blitter,"V11 blitter ACK");
		@(negedge clk); scanline_event=1; @(posedge clk); @(negedge clk); scanline_event=0; repeat (2) @(posedge clk);
		expect_value(interrupt_state==16'h0004 && !irq_scanline,"V11 scanline masked");
		reg_write(7'h05,16'h0044); expect_value(irq_scanline,"V11 enable pending scanline");
		reg_write(7'h04,5); repeat (3) @(posedge clk);
		expect_value(interrupt_state==16'h0044 && irq_blitter && irq_scanline,"V11 both pending");
		reg_write(7'h01,16'h0040); repeat (3) @(posedge clk);
		expect_value(interrupt_state==16'h0004 && !irq_blitter && irq_scanline,"V11 selective W1C");
		reg_write(7'h00,16'h000a); reg_read(7'h00,got); expect_value(got==16'h0007,"V11 status forced bits");
		reg_write(7'h03,16'h1234); reg_read(7'h03,got); expect_value(got==16'h00ef,"V11 flags read quirk");
		reg_write(7'h01,16'hffff); repeat (3) @(posedge clk);
		reg_write(7'h04,16'h1234); repeat (3) @(posedge clk);
		expect_value(interrupt_state==16'h0040,"V11 unknown command done");
		reg_write(7'h16,16'h00ef); reg_write(7'h19,16'h0106); reg_write(7'h1a,16'h0101);
		reg_write(7'h1b,16'h00f3); reg_write(7'h1c,16'h0003); reg_write(7'h1d,16'h01fc);
		reg_write(7'h1e,16'h01e4); reg_write(7'h1f,16'h01b2); reg_write(7'h20,16'h0032);
		reg_write(7'h22,16'h0021); reg_write(7'h26,16'h0043);
		expect_value(timing_int_scanline==16'h00ef && timing_vtotal==16'h0106 && timing_vsync==16'h0101 &&
			timing_vblank_start==16'h00f3 && timing_vblank_end==16'h0003 && timing_htotal==16'h01fc &&
			timing_hsync==16'h01e4 && timing_hblank_start==16'h01b2 && timing_hblank_end==16'h0032 &&
			display_yorigin1==16'h0021 && display_xorigin1==16'h0043,"V11 timing/origin exports");

		if (failures != 0)
			$fatal(1, "%0d of %0d checks failed", failures, tests);
		$display("PASS all %0d ITech32 blitter checks with randomized stalls", tests);
		$finish;
	end
endmodule
