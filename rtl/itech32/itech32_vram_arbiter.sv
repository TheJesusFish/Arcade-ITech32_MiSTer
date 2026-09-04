// SPDX-License-Identifier: GPL-2.0-or-later
// Buffered bridge from the blitter's 16-bit framebuffer port to shared DDR.
// Scanout uses a separate deadline-priority burst channel. Adjacent blitter
// pixels are gathered into native 64-bit DDR qwords before they enter the
// queue, reducing the scheduler work by up to four transactions without
// weakening read-after-write or durable-completion ordering.
`timescale 1ns/1ps

module itech32_vram_arbiter (
	input  logic        clk,
	input  logic        reset,

	input  logic        blit_req,
	input  logic        blit_we,
	input  logic        blit_plane,
	input  logic [18:0] blit_addr,
	input  logic [15:0] blit_wdata,
	output logic        blit_ack,
	output logic [15:0] blit_rdata,
	output logic        writes_pending,
	// A downstream elastic slice may retain the final accepted qword after this
	// arbiter's local queue is empty. Keep ordered reads behind that retained
	// write so the legacy read and gathered-write channels stay exclusive.
	input  logic        downstream_write_pending,

	// Legacy 16-bit channel is retained for ordered blitter reads.
	output logic        mem_req,
	output logic        mem_we,
	output logic [19:0] mem_addr,
	output logic [15:0] mem_wdata,
	output logic [1:0]  mem_be,
	input  logic        mem_ack,
	input  logic [15:0] mem_rdata,

	// Gathered writes use the native DDR qword shape. The token changes for
	// every new front entry, so equal-address consecutive qwords remain distinct
	// while all request fields stay stable until ACK.
	output logic        qwrite_req,
	output logic [17:0] qwrite_addr,
	output logic [63:0] qwrite_data,
	output logic [7:0]  qwrite_be,
	output logic        qwrite_token,
	input  logic        qwrite_ack
);

	localparam integer FIFO_ADDR_WIDTH = 8;
	localparam integer FIFO_DEPTH = 1 << FIFO_ADDR_WIDTH;
	localparam integer FIFO_DATA_WIDTH = 18 + 64 + 8;
	localparam integer GATHER_IDLE_CYCLES = 16;
	localparam integer GATHER_IDLE_WIDTH = $clog2(GATHER_IDLE_CYCLES);
	localparam logic [FIFO_ADDR_WIDTH:0] FIFO_DEPTH_COUNT =
		{1'b1, {FIFO_ADDR_WIDTH{1'b0}}};

	// A 256x90 queue retains at least the old 256-pixel worst-case capacity;
	// sequential traffic gains four times that capacity. The registered read is
	// the documented M10K simple-dual-port template and the array is not reset.
	(* ramstyle = "M10K, no_rw_check" *)
	logic [FIFO_DATA_WIDTH-1:0] write_fifo [0:FIFO_DEPTH-1];
	logic [FIFO_DATA_WIDTH-1:0] fifo_ram_q;
	logic [FIFO_ADDR_WIDTH-1:0] fifo_wr_ptr;
	logic [FIFO_ADDR_WIDTH-1:0] fifo_rd_ptr;
	logic [FIFO_ADDR_WIDTH:0]   fifo_count;

	logic        gather_valid;
	logic [17:0] gather_addr;
	logic [63:0] gather_data;
	logic [7:0]  gather_be;
	logic [GATHER_IDLE_WIDTH-1:0] gather_idle_count;
	logic        front_valid;
	logic [FIFO_DATA_WIDTH-1:0] front_data;
	logic        front_token;
	logic        next_valid;
	logic [FIFO_DATA_WIDTH-1:0] next_data;
	logic        read_pending;
	logic        read_active;
	logic [19:0] read_addr;

	logic [17:0] incoming_addr;
	logic [1:0]  incoming_lane;
	logic [15:0] incoming_raw_word;
	logic        incoming_write_offer;
	logic        incoming_write_ready;
	logic        write_output_valid;
	logic [17:0] write_output_addr;
	logic [1:0]  write_output_lane;
	logic [15:0] write_output_raw_word;
	logic        write_skid_valid;
	logic [17:0] write_skid_addr;
	logic [1:0]  write_skid_lane;
	logic [15:0] write_skid_raw_word;
	logic        write_output_ready;
	logic        write_offer;
	logic        same_gather;
	logic        fifo_full;
	logic        drain_empty;
	logic        emit_capacity;
	logic        idle_flush;
	logic        emit_gather;
	logic        write_accept;
	logic        write_direct;
	logic        fifo_write;
	logic        fifo_read;
	logic        front_pop;
	logic        write_backlog;

	assign incoming_addr = {blit_plane, blit_addr[18:2]};
	assign incoming_lane = blit_addr[1:0];
	assign incoming_raw_word = {blit_wdata[7:0], blit_wdata[15:8]};
	assign incoming_write_offer = !reset && !read_active && blit_req && blit_we;
	// This is the registered-ready cut at the blitter boundary. Once the skid
	// slot is occupied, the producer holds its request/payload until the slot
	// drains. No live address or gather comparison feeds this signal.
	assign incoming_write_ready = !write_skid_valid;
	assign write_offer = write_output_valid;
	assign same_gather = gather_valid && write_output_addr == gather_addr;
	assign fifo_full = fifo_count == FIFO_DEPTH_COUNT;
	assign drain_empty = !front_valid && !next_valid && !read_pending &&
		(fifo_count == 0);
	assign emit_capacity = drain_empty || !fifo_full;
	assign idle_flush = gather_valid && !write_offer &&
		((blit_req && !blit_we) ||
		 gather_idle_count == GATHER_IDLE_WIDTH'(GATHER_IDLE_CYCLES - 1));

	// A changed qword is admitted only if the previous gather can move into the
	// drain queue on the same edge. Same-qword pixels remain admissible even when
	// the queue is full because they consume no additional entry.
	assign write_output_ready = !gather_valid || same_gather || emit_capacity;
	assign write_accept = write_offer && write_output_ready;
	assign emit_gather = gather_valid && emit_capacity &&
		(idle_flush || (write_accept && !same_gather));
	assign write_direct = emit_gather && drain_empty;
	assign fifo_write = emit_gather && !write_direct;
	assign front_pop = front_valid && qwrite_ack;
	assign fifo_read = !reset && (fifo_count != 0) &&
		((!read_pending && (!next_valid || (front_pop && next_valid))) ||
		 (read_pending && front_pop && !next_valid));

	assign write_backlog = write_output_valid || write_skid_valid || gather_valid ||
		front_valid || next_valid || read_pending || (fifo_count != 0) ||
		downstream_write_pending || (blit_req && blit_we);
	assign writes_pending = write_backlog;

	// Writes complete when the input pixel is retained. Reads are admitted only
	// after every gathered qword has reached the DDR bridge and complete on the
	// legacy memory response.
	always_comb begin
		blit_ack = (incoming_write_offer && incoming_write_ready) ||
			(read_active && mem_ack);
		blit_rdata = mem_rdata;

		mem_req = read_active;
		mem_we = 1'b0;
		mem_addr = read_addr;
		mem_wdata = 16'd0;
		mem_be = 2'b11;

		qwrite_req = front_valid;
		qwrite_addr = front_data[89:72];
		qwrite_data = front_data[71:8];
		qwrite_be = front_data[7:0];
		qwrite_token = front_token;
	end

	// A two-entry registered-output skid slice breaks the former live
	// blit_addr -> gather compare -> blit_ack combinational loop. The output
	// entry may drain and be replaced every clock, retaining one-pixel-per-clock
	// throughput. Only occupancy resets; invalid payload flops are don't-care.
	always_ff @(posedge clk) begin
		if (reset) begin
			write_output_valid <= 1'b0;
			write_skid_valid <= 1'b0;
		end else begin
			if ((incoming_write_offer && incoming_write_ready) &&
				(write_output_valid && !write_output_ready)) begin
				write_skid_valid <= 1'b1;
			end else if (write_output_ready) begin
				write_skid_valid <= 1'b0;
			end

			if (incoming_write_offer && incoming_write_ready) begin
				write_skid_addr <= incoming_addr;
				write_skid_lane <= incoming_lane;
				write_skid_raw_word <= incoming_raw_word;
			end

			if (!write_output_valid || write_output_ready) begin
				write_output_valid <= incoming_write_offer || write_skid_valid;
				if (write_skid_valid) begin
					write_output_addr <= write_skid_addr;
					write_output_lane <= write_skid_lane;
					write_output_raw_word <= write_skid_raw_word;
				end else if (incoming_write_offer) begin
					write_output_addr <= incoming_addr;
					write_output_lane <= incoming_lane;
					write_output_raw_word <= incoming_raw_word;
				end
			end
		end
	end

	// Separate, reset-free storage process preserves canonical synchronous RAM
	// inference. Read and write pointers never target an ambiguous full-boundary
	// collision because a full FIFO stalls the gather emission for one cycle.
	always_ff @(posedge clk) begin
		if (fifo_write)
			write_fifo[fifo_wr_ptr] <= {gather_addr, gather_data, gather_be};
		if (fifo_read)
			fifo_ram_q <= write_fifo[fifo_rd_ptr];
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			fifo_wr_ptr <= '0;
			fifo_rd_ptr <= '0;
			fifo_count <= '0;
			gather_valid <= 1'b0;
			gather_addr <= 18'd0;
			gather_data <= 64'd0;
			gather_be <= 8'd0;
			gather_idle_count <= '0;
			front_valid <= 1'b0;
			front_data <= '0;
			front_token <= 1'b0;
			next_valid <= 1'b0;
			next_data <= '0;
			read_pending <= 1'b0;
			read_active <= 1'b0;
			read_addr <= 20'd0;
		end else begin
			case ({fifo_write, fifo_read})
				2'b10: fifo_count <= fifo_count + 1'b1;
				2'b01: fifo_count <= fifo_count - 1'b1;
				default: fifo_count <= fifo_count;
			endcase
			if (fifo_write)
				fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
			if (fifo_read) begin
				fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
				read_pending <= 1'b1;
			end

			if (read_pending) begin
				if (!fifo_read)
					read_pending <= 1'b0;
				if (!front_valid || front_pop) begin
					front_data <= fifo_ram_q;
					front_valid <= 1'b1;
					front_token <= !front_token;
				end else begin
					next_data <= fifo_ram_q;
					next_valid <= 1'b1;
				end
			end

			if (front_pop && !read_pending) begin
				if (next_valid) begin
					front_data <= next_data;
					front_valid <= 1'b1;
					front_token <= !front_token;
					next_valid <= 1'b0;
				end else begin
					front_valid <= 1'b0;
				end
			end else if (!front_valid && next_valid && !read_pending) begin
				front_data <= next_data;
				front_valid <= 1'b1;
				front_token <= !front_token;
				next_valid <= 1'b0;
			end

			if (write_direct) begin
				front_data <= {gather_addr, gather_data, gather_be};
				front_valid <= 1'b1;
				front_token <= !front_token;
			end

			// The blitter's raw-pixel pipeline has short request gaps between
			// adjacent writes. Preserve a partial qword across those gaps so they
			// still aggregate, but bound the final completion delay. Reads flush
			// immediately through idle_flush above to retain read-after-write order.
			if (write_accept || emit_gather) begin
				gather_idle_count <= '0;
			end else if (gather_valid && !write_offer &&
				gather_idle_count != GATHER_IDLE_WIDTH'(GATHER_IDLE_CYCLES - 1)) begin
				gather_idle_count <= gather_idle_count + 1'b1;
			end

			// Merge exact byte lanes so repeated writes to one pixel are last-wins.
			// A qword change emits the old gather and seeds the new one atomically.
			if (write_accept) begin
				if (!gather_valid || !same_gather) begin
					gather_valid <= 1'b1;
					gather_addr <= write_output_addr;
					gather_data <= 64'd0;
					gather_be <= 8'd0;
					gather_data[write_output_lane * 16 +: 16] <=
						write_output_raw_word;
					gather_be[write_output_lane * 2 +: 2] <= 2'b11;
				end else begin
					gather_data[write_output_lane * 16 +: 16] <=
						write_output_raw_word;
					gather_be[write_output_lane * 2 +: 2] <= 2'b11;
				end
			end else if (emit_gather) begin
				gather_valid <= 1'b0;
			end

			// A blitter read snapshots only after the final gathered qword ACK.
			if (!read_active && !write_backlog && blit_req && !blit_we) begin
				read_addr <= {blit_plane, blit_addr};
				read_active <= 1'b1;
			end else if (read_active && mem_ack) begin
				read_active <= 1'b0;
			end
		end
	end

`ifdef ITECH32_HW_PROBE
	wire [FIFO_ADDR_WIDTH:0] hw_fifo_level = fifo_count +
		{{FIFO_ADDR_WIDTH{1'b0}}, front_valid} +
		{{FIFO_ADDR_WIDTH{1'b0}}, next_valid} +
		{{FIFO_ADDR_WIDTH{1'b0}}, read_pending};
	logic [FIFO_ADDR_WIDTH:0] hw_fifo_high_water = '0;
	logic [31:0] hw_fifo_full_stall_cycles = 32'd0;
	logic [31:0] hw_pixel_write_accepts = 32'd0;
	logic [31:0] hw_qword_write_drains = 32'd0;
	logic [127:0] hw_fifo_probe = 128'd0;
	wire [0:0] hw_fifo_source;

	always_ff @(posedge clk) begin
		if (reset) begin
			hw_fifo_high_water <= '0;
			hw_fifo_full_stall_cycles <= 32'd0;
			hw_pixel_write_accepts <= 32'd0;
			hw_qword_write_drains <= 32'd0;
			hw_fifo_probe <= 128'd0;
		end else begin
			if (hw_fifo_level > hw_fifo_high_water)
				hw_fifo_high_water <= hw_fifo_level;
			if (write_offer && !write_accept)
				hw_fifo_full_stall_cycles <= hw_fifo_full_stall_cycles + 1'b1;
			if (write_accept)
				hw_pixel_write_accepts <= hw_pixel_write_accepts + 1'b1;
			if (front_pop)
				hw_qword_write_drains <= hw_qword_write_drains + 1'b1;
			hw_fifo_probe <= {
				8'ha8, 8'h03,
				hw_fifo_level, hw_fifo_high_water,
				hw_fifo_full_stall_cycles[29:0],
				hw_pixel_write_accepts, hw_qword_write_drains
			};
		end
	end

	altsource_probe #(
		.sld_auto_instance_index("YES"),
		.sld_instance_index(3),
		.instance_id("IVF"),
		.probe_width(128),
		.source_width(1),
		.source_initial_value("0"),
		.enable_metastability("NO")
	) fifoHardwareProbe (
		.probe(hw_fifo_probe),
		.source(hw_fifo_source)
	);
`endif

`ifndef SYNTHESIS
	logic        held_write_output_valid;
	logic [17:0] held_write_output_addr;
	logic [1:0]  held_write_output_lane;
	logic [15:0] held_write_output_raw_word;
	logic        held_qwrite_valid;
	logic [17:0] held_qwrite_addr;
	logic [63:0] held_qwrite_data;
	logic [7:0]  held_qwrite_be;
	logic        held_qwrite_token;
	always_ff @(posedge clk) begin
		if (reset) begin
			held_write_output_valid <= 1'b0;
			held_qwrite_valid <= 1'b0;
		end else begin
			if (held_write_output_valid) begin
				assert (write_output_valid)
					else $fatal(1, "VRAM write skid output dropped while stalled");
				assert ({write_output_addr, write_output_lane,
				         write_output_raw_word} ==
				        {held_write_output_addr, held_write_output_lane,
				         held_write_output_raw_word})
					else $fatal(1, "VRAM write skid payload changed while stalled");
			end
			held_write_output_valid <= write_output_valid && !write_output_ready;
			if (write_output_valid && !write_output_ready) begin
				held_write_output_addr <= write_output_addr;
				held_write_output_lane <= write_output_lane;
				held_write_output_raw_word <= write_output_raw_word;
			end
			assert (!(write_skid_valid && !write_output_valid))
				else $fatal(1, "VRAM write skid occupied without an output entry");

			if (qwrite_req && !held_qwrite_valid && !qwrite_ack) begin
				held_qwrite_valid <= 1'b1;
				held_qwrite_addr <= qwrite_addr;
				held_qwrite_data <= qwrite_data;
				held_qwrite_be <= qwrite_be;
				held_qwrite_token <= qwrite_token;
			end
			if (held_qwrite_valid && !qwrite_ack) begin
				assert (qwrite_req)
					else $fatal(1, "VRAM qword request dropped while stalled");
				assert ({qwrite_addr, qwrite_data, qwrite_be, qwrite_token} ==
				        {held_qwrite_addr, held_qwrite_data,
				         held_qwrite_be, held_qwrite_token})
					else $fatal(1, "VRAM qword payload changed while stalled");
			end
			if (held_qwrite_valid && qwrite_ack)
				held_qwrite_valid <= 1'b0;
			assert (!(mem_req && qwrite_req))
				else $fatal(1, "VRAM read overlapped gathered write drain");
			assert (fifo_count <= FIFO_DEPTH_COUNT)
				else $fatal(1, "VRAM qword FIFO overflow");
		end
	end
`endif

endmodule
