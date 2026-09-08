// SPDX-License-Identifier: GPL-3.0-or-later
// Shared MiSTer DDR3 store for the ITech32 ROM regions and framebuffer.
//
// DDRAM_ADDR addresses 64-bit words.  The byte-addressed image begins at
// 0x3000_0000, matching MiSTer's fast ROM-download staging area.  Within a
// 64-bit DDR word, bits [7:0] hold the byte at the lowest address.

`timescale 1ns/1ps

module itech32_ddr_memory #(
	parameter logic [31:0] DDR_BYTE_BASE = 32'h3000_0000,
	parameter logic [27:0] MAIN_BASE     = 28'h000_0000,
	parameter logic [27:0] SOUND_BASE    = 28'h040_0000,
	parameter logic [27:0] GROM_BASE     = 28'h050_0000,
	parameter logic [27:0] SAMPLE0_BASE  = 28'h260_0000,
	parameter logic [27:0] SAMPLE3_BASE  = 28'h2a0_0000,
	parameter logic [27:0] VRAM_BASE     = 28'h2e0_0000,
	parameter integer      VRAM_CLEAR_LINES = 262144,
	parameter bit          VRAM_WRITE_COMBINE = 1'b1,
	parameter integer      SCAN_BURST_WORDS = 97
) (
	input  logic        clk,
	input  logic        reset,
	input  logic        timekill_mode,
	input  logic        bloodstorm_mode,
	// Framework RESET reaches MiSTer's safe DDR terminator. Stop launching
	// new commands before that terminator locks, but let accepted commands
	// drain so the persistent loader/cache state survives a warm reset.
	input  logic        quiesce,
	output logic        quiesce_ack,

	// WIDE=1 hps_io stream. If Main_MiSTer performs a fast DDR download,
	// ioctl_download toggles without ioctl_wr and the data is already at
	// DDR_BYTE_BASE; ordinary streams are written here one 16-bit beat at a
	// time and throttled with ioctl_wait.
	input  logic        ioctl_download,
	input  logic        ioctl_wr,
	input  logic [15:0] ioctl_index,
	input  logic [26:0] ioctl_addr,
	input  logic [15:0] ioctl_data,
	output logic        ioctl_wait,
	output logic        rom_loaded,
	output logic        vector_load_we,
	output logic [4:0]  vector_load_addr,
	output logic [31:0] vector_load_wdata,
	output logic [3:0]  vector_load_be,

	input  logic        main_req,
	input  logic [21:0] main_addr,
	output logic        main_ack,
	output logic [31:0] main_rdata,

	input  logic        grom_req,
	input  logic [25:0] grom_addr,
	output logic        grom_ack,
	// The graphics client addresses bytes but receives the containing aligned
	// 64-bit qword.  Returning the native DDR/cache width lets the blitter
	// amortize one held request across eight sequential RLE bytes.
	output logic [63:0] grom_rdata,

	input  logic        sound_req,
	input  logic [18:0] sound_addr,
	output logic        sound_ack,
	output logic [7:0]  sound_rdata,

	// Byte address within one logical4MiB ES5506 region. SFTM populates0/3,
	// Time Killers2, BloodStorm0/2; empty banks return zero without DDR traffic.
	input  logic        sample_req,
	input  logic [1:0]  sample_bank,
	input  logic [21:0] sample_addr,
	output logic        sample_ack,
	output logic [15:0] sample_rdata,

	// Two 512x1024x16 planes, addressed as 20-bit words.
	input  logic        vram_req,
	input  logic        vram_we,
	input  logic [19:0] vram_addr,
	input  logic [15:0] vram_wdata,
	input  logic [1:0]  vram_be,
	output logic        vram_ack,
	output logic [15:0] vram_rdata,

	// Native-qword runtime writes gathered by the VRAM bridge. The address is
	// the 64-bit word index within the two-plane framebuffer. A toggling token
	// distinguishes consecutive same-address entries while the payload remains
	// stable through ACK.
	input  logic        vram_qwrite_req,
	input  logic [17:0] vram_qwrite_addr,
	input  logic [63:0] vram_qwrite_data,
	input  logic [7:0]  vram_qwrite_be,
	input  logic        vram_qwrite_token,
	output logic        vram_qwrite_ack,

	// Deadline channel for scanout. One accepted request reads the complete
	// qword-aligned active window as a SCAN_BURST_WORDS-beat DDR burst. Returned
	// beats are consecutive and cannot be backpressured by the consumer.
	input  logic        scan_req,
	input  logic [19:0] scan_addr,
	output logic        scan_accept,
	output logic        scan_data_valid,
	output logic [63:0] scan_rdata,
	output logic        scan_last,

	output logic        DDRAM_CLK,
	input  logic        DDRAM_BUSY,
	output logic [7:0]  DDRAM_BURSTCNT,
	output logic [28:0] DDRAM_ADDR,
	input  logic [63:0] DDRAM_DOUT,
	input  logic        DDRAM_DOUT_READY,
	output logic [63:0] DDRAM_DIN,
	output logic [7:0]  DDRAM_BE,
	output logic        DDRAM_RD,
	output logic        DDRAM_WE
);
	localparam logic [2:0] CLIENT_MAIN   = 3'd0;
	localparam logic [2:0] CLIENT_GROM   = 3'd1;
	localparam logic [2:0] CLIENT_SOUND  = 3'd2;
	localparam logic [2:0] CLIENT_SAMPLE = 3'd3;
	localparam logic [2:0] CLIENT_VRAM   = 3'd4;
	localparam logic [2:0] CLIENT_LOADER = 3'd5;
	localparam logic [2:0] CLIENT_VECTOR = 3'd6;
	localparam logic [2:0] CLIENT_CLEAR  = 3'd7;
	localparam integer CLEAR_COUNTER_WIDTH =
		(VRAM_CLEAR_LINES <= 2) ? 1 : $clog2(VRAM_CLEAR_LINES);
	localparam logic [CLEAR_COUNTER_WIDTH-1:0] CLEAR_LAST =
		CLEAR_COUNTER_WIDTH'(VRAM_CLEAR_LINES - 1);
	localparam integer MAIN_CACHE_SET_BITS = 5;
	localparam integer MAIN_CACHE_SETS = 1 << MAIN_CACHE_SET_BITS;
	localparam integer MAIN_CACHE_TAG_BITS = 22 - 7 - MAIN_CACHE_SET_BITS;

	typedef enum logic [4:0] {
		ST_IDLE         = 5'd0,
		ST_DISPATCH     = 5'd1,
		ST_ISSUE        = 5'd2,
		ST_WAIT_READ    = 5'd3,
		ST_WAIT_WRITE   = 5'd4,
		ST_VECTOR_SECOND = 5'd5,
		ST_VECTOR_FINISH = 5'd6,
		ST_CAPTURE      = 5'd7,
		ST_RESPOND      = 5'd8,
		ST_LOOKUP_RESULT = 5'd9,
		ST_SELECT       = 5'd10,
		ST_SCAN_ISSUE   = 5'd11,
		ST_SCAN_WAIT    = 5'd12,
		ST_GROM_BURST_ISSUE = 5'd14,
		ST_GROM_BURST_WAIT  = 5'd15,
		ST_MAIN_BURST_ISSUE = 5'd17,
		ST_MAIN_BURST_WAIT  = 5'd18,
		ST_VRAM_BURST_WRITE = 5'd19
	} state_t;

	typedef enum logic [2:0] {
		MF_FREE            = 3'd0,
		MF_PROBE           = 3'd1,
		MF_HIT_RESPONSE    = 3'd2,
		MF_MISS_WAIT       = 3'd3,
		MF_REFILL_PROBE    = 3'd4,
		MF_REFILL_RESPONSE = 3'd5,
		MF_WAIT_RELEASE    = 3'd6
	} main_front_state_t;

	typedef enum logic [2:0] {
		GF_FREE         = 3'd0,
		GF_PROBE        = 3'd1,
		GF_RESPONSE     = 3'd2,
		GF_MISS_WAIT    = 3'd3,
		GF_WAIT_RELEASE = 3'd4
	} grom_front_state_t;

	typedef enum logic [2:0] {
		SF_FREE         = 3'd0,
		SF_HIT_RESPONSE = 3'd1,
		SF_MISS_WAIT    = 3'd2,
		SF_WAIT_RELEASE = 3'd3,
		SF_PROBE_RESULT = 3'd4
	} sound_front_state_t;

	state_t state;
	main_front_state_t main_front_state;
	grom_front_state_t grom_front_state;
	sound_front_state_t sound_front_state;
	// A deliberate carrier change may stop DDRAM_CLK only after this service
	// has retired or cancelled every physical transaction. Retained write-window
	// data is local state and is safe to resume after the clock returns.
	assign quiesce_ack = quiesce && state == ST_IDLE && !DDRAM_RD && !DDRAM_WE;
	// The 6809 alternates fixed and banked program regions whose physical lines
	// can share a low-nine-qword index. Two registered ways retain one line from
	// each region without changing the three-edge local hit contract. Each way is
	// a canonical synchronous 1W/1R M10K body; only validity resets.
	(* ramstyle = "M10K, no_rw_check" *) logic [70:0] sound_cache_way0 [0:511];
	(* ramstyle = "M10K, no_rw_check" *) logic [70:0] sound_cache_way1 [0:511];
	logic [70:0] sound_cache_way0_q;
	logic [70:0] sound_cache_way1_q;
	logic [511:0] sound_cache_valid_way0;
	logic [511:0] sound_cache_valid_way1;
	// One bit per set names the next victim only when both ways are valid. It is
	// intentionally not reset: invalid-first fill makes stale state unobservable.
	logic [511:0] sound_cache_victim;
	logic sound_cache_refill;
	logic sound_cache_publish;
	logic [18:0] sound_front_addr_q;
	logic [7:0]  sound_front_data_q;
	logic        sound_front_hit_q;
	logic        sound_front_hit_way_q;
	logic [1:0]  sound_front_valid_q;
	logic        sound_front_victim_q;
	logic        sound_front_refill_way_q;
	logic        sound_front_way0_hit;
	logic        sound_front_way1_hit;
	logic [7:0]  sound_front_way0_data;
	logic [7:0]  sound_front_way1_data;
	logic        sound_cache_hit_touch;
	logic        sound_probe_start;
	logic        sound_miss_scheduler_active;
	logic        sound_miss_pending;
	// Four additional sample grants are allowed while a SOUND miss waits.
	// This is an arbitration bound, not a bound on external DDR waitrequest.
	logic [2:0]  sound_sample_grants;

	logic [4:0] served;
	logic [38:0] served_signature [0:4];
	logic [2:0] rr_client;
	logic [4:0] pending_clients;
	logic [4:0] pending_clients_q;
	logic       selected_valid;
	logic [2:0] selected_client;
	logic [27:0] capture_byte_addr;
	logic [27:0] capture_line_addr;
	logic        capture_write;
	logic        capture_vram_qwrite;
	logic        capture_cacheable;
	logic        capture_sample_empty;
	logic [25:0] grom_effective_addr;

	// 8.5MiB is17 pages of512KiB. Reduce the7-bit page, leaving the19
	// byte-offset wires untouched; three narrow subtracts cover all26-bit
	// source addresses without a wide divider or a new pipeline/handshake.
	function automatic logic [25:0] rev1_grom_offset(input logic [25:0] address);
		logic [6:0] page;
		begin
			page = address[25:19];
			if (page >= 7'd68) page = page - 7'd68;
			if (page >= 7'd34) page = page - 7'd34;
			if (page >= 7'd17) page = page - 7'd17;
			rev1_grom_offset = {page, address[18:0]};
		end
	endfunction
	logic [38:0] capture_signature;
	logic        vram_client_req;
	logic        vram_client_write;
	logic [38:0] live_vram_signature;
	logic [63:0] vram_payload_data;
	logic [7:0]  vram_payload_be;
	logic [27:0] live_vram_line_addr;
	logic [27:0] live_vram_block_addr;
	logic [3:0]  live_vram_buffer_index;
	logic [17:0] live_scan_row_index;
	logic        scan_write_buffer_conflict;
	logic [25:0] grom_front_addr_q;
	logic [25:0] grom_front_effective_q;
	logic        grom_front_hit_q;
	logic        grom_front_cancel;
	logic        grom_miss_scheduler_active;
	logic        grom_miss_pending;
	logic        grom_fast_response_valid;
	logic        vram_fast_write;

	// The 68020 fetches instruction words from framework DDR. Thirty-two direct-
	// mapped 128-byte lines turn sequential fetches and short branch loops into
	// synchronous embedded-memory hits while keeping the complete 4 MiB ROM in
	// DDR. Tags stay in flops; only the reset-free 32 Kibit data body is forced
	// into M10K, following Intel's registered-read template.
	(* ramstyle = "M10K, no_rw_check" *) logic [63:0] main_read_ahead [0:511];
	logic [63:0] main_read_ahead_q;
	logic [21:0] main_front_addr_q;
	logic        main_front_hit_q;
	logic [2:0]  main_front_byte_q;
	logic        main_front_collision_q;
	logic        main_probe_start;
	logic        main_probe_enable;
	logic [21:0] main_probe_addr;
	logic        main_probe_same_set;
	logic        main_probe_same_word;
	logic        main_front_cancel;
	logic        main_miss_scheduler_active;
	logic        main_miss_pending;
	logic        main_refill_write;
	logic        main_refill_same_set;
	logic        main_refill_same_word;
	logic [MAIN_CACHE_SETS-1:0] main_read_ahead_valid;
	logic [MAIN_CACHE_TAG_BITS-1:0] main_read_ahead_tag [0:MAIN_CACHE_SETS-1];
	logic [27:0] main_prefetch_line_q;
	logic [MAIN_CACHE_TAG_BITS-1:0] main_prefetch_tag_q;
	logic [MAIN_CACHE_SET_BITS-1:0] main_prefetch_set_q;
	logic [3:0]  main_prefetch_beat;
	logic        main_prefetch_discard;

	// The blitter consumes long, sequential raw/RLE byte streams.  A single
	// 64-bit cache beat made every eighth byte contend with scanout and audio
	// for a complete random DDR transaction. Keep one 128-byte read-ahead line
	// in an M10K and fill it with a 16-beat DDR burst. The 32 MiB graphics ROM
	// remains in framework DDR; only the blitter's immediate sequential working
	// set occupies embedded memory.
	(* ramstyle = "M10K, no_rw_check" *) logic [63:0] grom_read_ahead [0:15];
	logic [63:0] grom_read_ahead_q;
	logic        grom_read_ahead_valid;
	logic [18:0] grom_read_ahead_tag;
	logic [27:0] grom_prefetch_line_q;
	logic [18:0] grom_prefetch_tag_q;
	logic [3:0]  grom_prefetch_beat;
	logic        grom_prefetch_discard;

	// Sixty-four adjacent 16-bit framebuffer pixels share one 128-byte Avalon
	// burst window. The blitter commonly writes complete sequential runs, so
	// retaining sixteen qwords locally amortizes HPS-DDR command latency across
	// as many as sixteen accepted write beats. Byte enables retain exact partial-
	// write semantics; reads, an overlapping scanline, or a different window
	// force the current window durable before they proceed.
	logic        vram_write_buffer_valid;
	logic [27:0] vram_write_buffer_base;
	// Two physical banks: immutable drain ownership and a separate collector.
	// Swap pointers at flush; never copy or reset the wide data body.
	logic [63:0] vram_write_buffer_data [0:31];
	logic [7:0]  vram_write_buffer_be [0:31];
	logic        vram_collect_bank;
	logic        vram_drain_bank;
	logic        vram_drain_valid;
	logic [27:0] vram_drain_base;
	logic [3:0]  vram_drain_first;
	logic [3:0]  vram_write_buffer_first;
	logic [3:0]  vram_write_buffer_last;
	logic        vram_write_buffer_retry;
	logic [3:0]  vram_write_burst_index;
	logic [4:0]  vram_write_burst_count;
	logic [4:0]  vram_write_burst_accepted;
	logic        vram_fast_pending;
	logic [27:0] vram_fast_base_q;
	logic [3:0]  vram_fast_index_q;
	logic [31:0] vram_fast_select_q;
	logic [63:0] vram_fast_data_q;
	logic [7:0]  vram_fast_be_q;
	logic        vram_buffer_commit;

	logic [63:0] cache_data [0:4];
	logic [24:0] cache_tag  [0:4];
	logic [4:0]  cache_valid;

	logic        loader_pending;
	logic [26:0] loader_addr;
	logic [15:0] loader_data;
	logic        download_ended;
	logic        previous_download;
	logic        rom_download_active;
	logic        rom_download_started;
	logic        rom_download_finished;
	logic [3:0]  vector_line;
	logic [63:0] vector_line_data;
	logic        clear_active;
	logic [CLEAR_COUNTER_WIDTH-1:0] clear_line;

	logic [2:0] op_client;
	logic        op_write;
	logic        op_vram_qwrite;
	logic [27:0] op_byte_addr;
	logic [27:0] op_line_addr;
	logic [63:0] op_wdata;
	logic [7:0]  op_be;
	logic [38:0] op_signature;
	logic        op_cacheable;
	logic        op_sample_empty;
	logic        discard_inflight;
	logic [63:0] response_line;
	logic [2:0]  response_byte_index;
	logic [4:0]  response_clients;
	logic [38:0] response_signature;
	logic cache_lookup_hit;
	// MiSTer's safe DDR terminator can finish a write which was stalled when
	// framework RESET arrived using zero byte enables. Remember that reset
	// touched the handshake so durable loader/clear/runtime writes are retried
	// instead of being acknowledged as if their payload reached DDR.
	logic        write_quiesced;

	// Registered scan-request boundary. Cycle schedule:
	//   S0: scanout holds scan_req/scan_addr until scan_accept.
	//   S1: ST_IDLE captures scan_addr_q and enters ST_SCAN_ISSUE.
	//   S2: ST_SCAN_ISSUE either flushes a conflicting retained write window or
	//       launches the configured active-window read and pulses scan_accept.
	// The no-conflict request-to-DDR latency and accept timing are unchanged.
	// Only the conflict decision moves behind the existing address register, so
	// scanout coordinates no longer cross the scheduler into DDRAM_DIN in one
	// 100-MHz cycle.
	logic [19:0] scan_addr_q;
	logic [6:0]  scan_beat;
	logic        scan_discard;

	integer arb_step;
	integer arb_index;
	integer main_tag_index;
	integer vram_buffer_index;
	integer vram_byte_index;

	function automatic logic [7:0] line_byte(
		input logic [63:0] line,
		input logic [2:0] index
	);
		line_byte = line[index * 8 +: 8];
	endfunction

	function automatic logic [15:0] line_word_be(
		input logic [63:0] line,
		input logic [2:0] index
	);
		line_word_be = {
			line_byte(line, {index[2:1], 1'b0}),
			line_byte(line, {index[2:1], 1'b1})
		};
	endfunction

	function automatic logic [31:0] line_dword_be(
		input logic [63:0] line,
		input logic [2:0] index
	);
		logic [2:0] base;
		begin
			base = {index[2], 2'b00};
			line_dword_be = {
				line_byte(line, base),
				line_byte(line, base + 3'd1),
				line_byte(line, base + 3'd2),
				line_byte(line, base + 3'd3)
			};
		end
	endfunction

	function automatic logic [2:0] next_client(input logic [2:0] client);
		if (client == CLIENT_VRAM)
			next_client = CLIENT_MAIN;
		else
			next_client = client + 3'd1;
	endfunction

	function automatic logic [28:0] physical_word_addr(
		input logic [27:0] line_addr
	);
		logic [31:0] byte_addr;
		begin
			byte_addr = DDR_BYTE_BASE + {4'd0, line_addr};
			physical_word_addr = byte_addr[31:3];
		end
	endfunction

	// Both way reads complete at T1. Extract eight bits per way before the final
	// select so the response register never sees a 64-bit way mux.
	assign sound_front_way0_hit = sound_front_valid_q[0] &&
		sound_cache_way0_q[70:64] == sound_front_addr_q[18:12];
	assign sound_front_way1_hit = sound_front_valid_q[1] &&
		sound_cache_way1_q[70:64] == sound_front_addr_q[18:12];
	assign sound_front_way0_data = line_byte(sound_cache_way0_q[63:0],
		sound_front_addr_q[2:0]);
	assign sound_front_way1_data = line_byte(sound_cache_way1_q[63:0],
		sound_front_addr_q[2:0]);
	assign sound_cache_hit_touch = !main_front_cancel &&
		sound_front_state == SF_HIT_RESPONSE && sound_req &&
		sound_addr == sound_front_addr_q && sound_front_hit_q;

	always_comb begin
		rom_download_started = !previous_download && ioctl_download &&
			ioctl_index == 16'h0000;
		rom_download_finished = previous_download && !ioctl_download &&
			rom_download_active;
		main_front_cancel = quiesce || loader_pending || rom_download_active ||
			rom_download_started || rom_download_finished || download_ended ||
			clear_active;
		main_miss_scheduler_active = state == ST_MAIN_BURST_ISSUE ||
			state == ST_MAIN_BURST_WAIT;
		main_miss_pending = main_front_state == MF_MISS_WAIT && main_req &&
			main_addr == main_front_addr_q && !main_front_cancel &&
			!main_miss_scheduler_active;
		main_refill_write = state == ST_MAIN_BURST_WAIT && DDRAM_DOUT_READY;
		main_refill_same_set = main_miss_scheduler_active &&
			main_prefetch_set_q == main_front_addr_q[11:7];
		main_refill_same_word = main_refill_write &&
			{main_prefetch_set_q, main_prefetch_beat} ==
				{main_front_addr_q[11:7], main_front_addr_q[6:3]};
		// main_addr is already registered by main_bus. Launch the synchronous
		// read at acceptance, while capturing the identical request signature.
		// Refill probes still use the held address after complete publication.
		main_probe_start = main_req && !main_miss_scheduler_active &&
			((main_front_state == MF_FREE) ||
			 (main_front_state == MF_WAIT_RELEASE && main_addr != main_front_addr_q));
		main_probe_enable = !main_front_cancel && (main_probe_start ||
			((main_front_state == MF_PROBE || main_front_state == MF_REFILL_PROBE) &&
			 main_req && main_addr == main_front_addr_q));
		main_probe_addr = main_probe_start ? main_addr : main_front_addr_q;
		main_probe_same_set = main_miss_scheduler_active &&
			main_prefetch_set_q == main_probe_addr[11:7];
		main_probe_same_word = main_refill_write &&
			{main_prefetch_set_q, main_prefetch_beat} == main_probe_addr[11:3];
		grom_front_cancel = main_front_cancel;
		grom_miss_scheduler_active = state == ST_GROM_BURST_ISSUE ||
			state == ST_GROM_BURST_WAIT;
		grom_miss_pending = grom_front_state == GF_MISS_WAIT && grom_req &&
			grom_addr == grom_front_addr_q && !grom_front_cancel &&
			!grom_miss_scheduler_active;
		// A canceled accepted read may still physically complete. Its data/tag
		// can be written but the entry is not published; reload invalidation is
		// stronger still. Keep the RAM write-enable path local and narrow.
		sound_cache_refill = state == ST_WAIT_READ && DDRAM_DOUT_READY &&
			op_client == CLIENT_SOUND && !reset;
		sound_cache_publish = !main_front_cancel && !discard_inflight &&
			sound_front_state == SF_MISS_WAIT && sound_req &&
			sound_addr == sound_front_addr_q &&
			op_signature == {20'd0, sound_front_addr_q};
		// op_client remains latched during independent burst states. Only the
		// generic command states below actually own a SOUND miss/refill.
		sound_miss_scheduler_active = op_client == CLIENT_SOUND &&
			(state == ST_CAPTURE || state == ST_DISPATCH ||
			 state == ST_LOOKUP_RESULT || state == ST_ISSUE ||
			 state == ST_WAIT_READ || state == ST_RESPOND);
		sound_probe_start = !main_front_cancel && sound_req &&
			!sound_miss_scheduler_active &&
			(sound_front_state == SF_FREE ||
			 (sound_front_state == SF_WAIT_RELEASE &&
			  sound_addr != sound_front_addr_q));
		sound_miss_pending = sound_front_state == SF_MISS_WAIT && sound_req &&
			sound_addr == sound_front_addr_q && !main_front_cancel &&
			!sound_miss_scheduler_active;
		vram_client_req = vram_qwrite_req || vram_req;
		vram_client_write = vram_qwrite_req || (vram_req && vram_we);
		live_vram_signature = vram_qwrite_req
			? {19'd0, vram_qwrite_token, 1'b1, vram_qwrite_addr}
			: {vram_we, vram_addr, vram_wdata, vram_be};
		pending_clients = {
			vram_client_req && (!served[CLIENT_VRAM] ||
				served_signature[CLIENT_VRAM] !=
					live_vram_signature),
			sample_req && (!served[CLIENT_SAMPLE] ||
				served_signature[CLIENT_SAMPLE] !=
				{15'd0, sample_bank, sample_addr}),
			sound_miss_pending,
			grom_miss_pending,
			main_miss_pending
		};

		// Selection consumes only the previous cycle's registered request
		// snapshot. A VRAM request is deadline-sensitive while scanout owns the
		// board-side port, so service that finite line burst ahead of background
		// CPU/GROM/audio traffic. When VRAM is idle the original round-robin order
		// retains fairness among every other client. Producers hold req and payload
		// through ACK, so this timing boundary cannot change transaction identity.
		selected_valid  = 1'b0;
		selected_client = rr_client;
		if (pending_clients_q[CLIENT_VRAM]) begin
			selected_valid  = 1'b1;
			selected_client = CLIENT_VRAM;
		end
		for (arb_step = 0; arb_step < 5; arb_step = arb_step + 1) begin
			arb_index = {29'd0, rr_client} + arb_step;
			if (arb_index >= 5)
				arb_index = arb_index - 5;
			if (!selected_valid && pending_clients_q[arb_index]) begin
				selected_valid  = 1'b1;
				selected_client = arb_index[2:0];
			end
		end

		// Arbitration ends at the registered op_client grant. Address and
		// signature selection use that grant during ST_CAPTURE on the following
		// cycle, so an unrelated request cannot feed an operation payload.
		capture_byte_addr   = 28'd0;
		capture_write       = 1'b0;
		capture_vram_qwrite = 1'b0;
		capture_cacheable   = 1'b1;
		capture_sample_empty = 1'b0;
		capture_signature   = 39'd0;
		// MAME wraps every ITech32 blitter source byte by the actual
		// 0x2080000-byte SFTM GROM region. The 26-bit source address cannot
		// reach twice that size, so one subtract is the exact modulo.
		grom_effective_addr = (timekill_mode || bloodstorm_mode) ? rev1_grom_offset(grom_addr) :
			((grom_addr >= 26'h2080000) ? grom_addr - 26'h2080000 : grom_addr);
		case (op_client)
			CLIENT_MAIN: begin
				// The selected grant fixes client ownership while the producer
				// holds its request and address through the eventual ACK.
				capture_byte_addr = MAIN_BASE +
					{6'd0, main_addr[21:2], 2'b00};
				capture_signature = {17'd0, main_addr};
			end
			CLIENT_SOUND: begin
				capture_byte_addr = SOUND_BASE + {9'd0, sound_front_addr_q};
				capture_signature = {20'd0, sound_front_addr_q};
			end
			CLIENT_SAMPLE: begin
				// SAMPLE3_BASE is the existing second populated4MiB slot;
				// BloodStorm maps its logical bank2 there, not TK's bank2 slot.
				capture_byte_addr = ((bloodstorm_mode ? sample_bank == 2'd2 :
					(!timekill_mode && sample_bank == 2'd3)) ?
					SAMPLE3_BASE : SAMPLE0_BASE)
					+ {6'd0, sample_addr[21:1], 1'b0};
				capture_sample_empty = bloodstorm_mode ? sample_bank[0] :
					timekill_mode ? sample_bank != 2'd2 :
					(sample_bank == 2'd1 || sample_bank == 2'd2);
				capture_signature = {15'd0, sample_bank, sample_addr};
			end
			CLIENT_VRAM: begin
				capture_byte_addr = vram_qwrite_req
					? VRAM_BASE + {7'd0, vram_qwrite_addr, 3'b000}
					: VRAM_BASE + {7'd0, vram_addr, 1'b0};
				capture_write = vram_client_write;
				capture_vram_qwrite = vram_qwrite_req;
				capture_cacheable = !vram_client_write;
				capture_signature = live_vram_signature;
			end
			default: begin end
		endcase
		capture_line_addr = {capture_byte_addr[27:3], 3'b000};

		// Pack the only runtime write payload directly from the VRAM producer.
		// The registered grant gates its use in ST_CAPTURE; sample/GROM/sound/main
		// selection has no combinational path into these payload values.
		vram_payload_data = vram_qwrite_req ? vram_qwrite_data : 64'd0;
		vram_payload_be = vram_qwrite_req ? vram_qwrite_be : 8'd0;
		if (!vram_qwrite_req) begin
			vram_payload_data[vram_addr[1:0] * 16 +: 16] =
				{vram_wdata[7:0], vram_wdata[15:8]};
			vram_payload_be[vram_addr[1:0] * 2 +: 2] =
				{vram_be[0], vram_be[1]};
		end
		live_vram_line_addr = vram_qwrite_req
			? VRAM_BASE + {7'd0, vram_qwrite_addr, 3'b000}
			: VRAM_BASE + {7'd0, vram_addr[19:2], 3'b000};
		live_vram_block_addr = {live_vram_line_addr[27:7], 7'b000_0000};
		live_vram_buffer_index = live_vram_line_addr[6:3];
		live_scan_row_index = VRAM_BASE[27:10] + {7'd0, scan_addr_q[19:9]};
		// Scanout issues a qword-aligned linear burst. Keep the deliberately
		// conservative two-row conflict fence: some programmed origins cross the
		// logical row, and flushing on every nonzero origin cannot expose stale
		// retained writes even though the shortened active window may end earlier.
		scan_write_buffer_conflict =
			live_scan_row_index == vram_write_buffer_base[27:10] ||
			(scan_addr_q[8:0] != 9'd0 &&
			 (live_scan_row_index + 18'd1) ==
				vram_write_buffer_base[27:10]);
		// Both ROM fronts own hits independently of the shared DDR scheduler.
		// GROM exposes the synchronous RAM output after its registered probe,
		// with no extra ACK register. Reload/quiesce synchronously cancel the
		// board consumer and front owner on the same edge, as in the old path.
		// Keep that global control tree off the local registered-data response.
		grom_fast_response_valid = grom_front_state == GF_RESPONSE &&
			grom_front_hit_q;
		vram_fast_write = VRAM_WRITE_COMBINE &&
			pending_clients[CLIENT_VRAM] && vram_client_write &&
			(vram_fast_pending
				? live_vram_block_addr == vram_fast_base_q
				: (!vram_write_buffer_valid ||
					vram_write_buffer_base == live_vram_block_addr));
		vram_buffer_commit = vram_fast_pending && !main_front_cancel &&
			((state == ST_IDLE && !vram_write_buffer_retry) ||
			 (state == ST_VRAM_BURST_WRITE && !write_quiesced));

		DDRAM_CLK = clk;
		DDRAM_BURSTCNT = (state == ST_SCAN_ISSUE || state == ST_SCAN_WAIT)
			? 8'(SCAN_BURST_WORDS) : ((state == ST_GROM_BURST_ISSUE ||
				state == ST_GROM_BURST_WAIT ||
				state == ST_MAIN_BURST_ISSUE ||
				state == ST_MAIN_BURST_WAIT) ? 8'd16 :
				(state == ST_VRAM_BURST_WRITE
					? {3'd0, vram_write_burst_count} : 8'd1));
		ioctl_wait = loader_pending ||
			(op_client == CLIENT_LOADER && state != ST_IDLE);
	end

	always_comb begin
		grom_ack = grom_fast_response_valid;
		grom_rdata = grom_read_ahead_q;
	end

	// Canonical synchronous old-data RAM templates. The single-outstanding SOUND
	// owner prevents a probe during refill, so no same-edge RDW value is consumed
	// (asserted below). No reset or bulk clear touches either RAM body.
	always_ff @(posedge clk) begin
		if (sound_cache_refill && !sound_front_refill_way_q)
			sound_cache_way0[op_signature[11:3]] <=
				{op_signature[18:12], DDRAM_DOUT};
		if (sound_probe_start)
			sound_cache_way0_q <= sound_cache_way0[sound_addr[11:3]];
	end

	always_ff @(posedge clk) begin
		if (sound_cache_refill && sound_front_refill_way_q)
			sound_cache_way1[op_signature[11:3]] <=
				{op_signature[18:12], DDRAM_DOUT};
		if (sound_probe_start)
			sound_cache_way1_q <= sound_cache_way1[sound_addr[11:3]];
	end

	always_ff @(posedge clk) begin
		main_ack   <= 1'b0;
		sound_ack  <= 1'b0;
		sample_ack <= 1'b0;
		vram_ack   <= 1'b0;
		vram_qwrite_ack <= 1'b0;
		scan_accept <= 1'b0;
		scan_data_valid <= 1'b0;
		scan_last <= 1'b0;
		vector_load_we <= 1'b0;

		previous_download <= ioctl_download;
		if (rom_download_started) begin
			rom_download_active <= 1'b1;
			rom_loaded <= 1'b0;
			cache_valid <= 5'd0;
			main_read_ahead_valid <= '0;
			download_ended <= 1'b0;
			vector_line <= 4'd0;
			clear_active <= 1'b0;
			clear_line <= '0;
		end
		if (rom_download_finished) begin
			download_ended <= 1'b1;
			rom_download_active <= 1'b0;
			// A runtime read accepted before the download may return after
			// the rising-edge invalidation. Invalidate again at the staging
			// boundary before reset-vector readback starts.
			cache_valid <= 5'd0;
			main_read_ahead_valid <= '0;
		end

		// A held request is one transaction until either req falls or its full
		// payload changes. This blocks delayed registered producers from being
		// acknowledged twice, while allowing ES/GROM no-gap next-address reads.
		if (!main_req)   served[CLIENT_MAIN] <= 1'b0;
		if (!grom_req)   served[CLIENT_GROM] <= 1'b0;
		if (!sound_req)  served[CLIENT_SOUND] <= 1'b0;
		if (!sample_req) served[CLIENT_SAMPLE] <= 1'b0;
		if (!vram_client_req) served[CLIENT_VRAM] <= 1'b0;

		if (ioctl_download && ioctl_wr && ioctl_index == 16'h0000 && !ioctl_wait) begin
			loader_pending <= 1'b1;
			loader_addr <= ioctl_addr;
			loader_data <= ioctl_data;
			rom_loaded <= 1'b0;
		end

		if (reset) begin
			state             <= ST_IDLE;
			main_front_state  <= MF_FREE;
			grom_front_state  <= GF_FREE;
			sound_front_state <= SF_FREE;
			sound_front_addr_q <= 19'd0;
			sound_front_data_q <= 8'hff;
			sound_front_hit_q <= 1'b0;
			sound_front_hit_way_q <= 1'b0;
			sound_front_valid_q <= 2'b00;
			sound_front_victim_q <= 1'b0;
			sound_front_refill_way_q <= 1'b0;
			sound_cache_valid_way0 <= '0;
			sound_cache_valid_way1 <= '0;
			sound_sample_grants <= 3'd0;
			served            <= 5'd0;
			rr_client         <= CLIENT_MAIN;
			grom_front_addr_q <= 26'd0;
			grom_front_effective_q <= 26'd0;
			pending_clients_q <= 5'd0;
			cache_valid       <= 5'd0;
			loader_pending    <= 1'b0;
			loader_addr       <= 27'd0;
			loader_data       <= 16'd0;
			download_ended    <= 1'b0;
			previous_download <= 1'b0;
			rom_download_active <= 1'b0;
			rom_loaded        <= 1'b0;
			vector_line       <= 4'd0;
			vector_line_data  <= 64'd0;
			clear_active      <= 1'b0;
			clear_line        <= '0;
			vector_load_we    <= 1'b0;
			vector_load_addr  <= 5'd0;
			vector_load_wdata <= 32'd0;
			vector_load_be    <= 4'hf;
			op_client         <= CLIENT_MAIN;
			op_write          <= 1'b0;
			op_vram_qwrite   <= 1'b0;
			op_byte_addr      <= 28'd0;
			op_line_addr      <= 28'd0;
			op_wdata          <= 64'd0;
			op_be             <= 8'd0;
			op_signature      <= 39'd0;
			op_cacheable      <= 1'b0;
			op_sample_empty   <= 1'b0;
			discard_inflight  <= 1'b0;
			write_quiesced    <= 1'b0;
			vram_write_buffer_valid <= 1'b0;
			vram_collect_bank <= 1'b0;
			vram_drain_bank <= 1'b1;
			vram_drain_valid <= 1'b0;
			vram_drain_base <= 28'd0;
			vram_drain_first <= 4'd0;
			vram_write_buffer_base <= 28'd0;
			vram_write_buffer_first <= 4'd0;
			vram_write_buffer_last <= 4'd0;
			vram_write_buffer_retry <= 1'b0;
			vram_write_burst_index <= 4'd0;
			vram_write_burst_count <= 5'd1;
			vram_write_burst_accepted <= 5'd0;
			vram_fast_pending <= 1'b0;
			vram_fast_base_q <= 28'd0;
			vram_fast_index_q <= 4'd0;
			vram_fast_select_q <= 32'd0;
			vram_fast_data_q <= 64'd0;
			vram_fast_be_q <= 8'd0;
			response_line     <= 64'd0;
			response_byte_index <= 3'd0;
			response_clients  <= 5'd0;
			response_signature <= 39'd0;
			cache_lookup_hit   <= 1'b0;
			scan_addr_q        <= 20'd0;
			scan_beat          <= 7'd0;
			scan_discard       <= 1'b0;
			served_signature[0] <= 39'd0;
			served_signature[1] <= 39'd0;
			served_signature[2] <= 39'd0;
			served_signature[3] <= 39'd0;
			served_signature[4] <= 39'd0;
			DDRAM_ADDR        <= 29'd0;
			DDRAM_DIN         <= 64'd0;
			DDRAM_BE          <= 8'd0;
			DDRAM_RD          <= 1'b0;
			DDRAM_WE          <= 1'b0;
			main_rdata        <= 32'hffff_ffff;
			main_front_addr_q <= 22'd0;
			main_front_hit_q <= 1'b0;
			main_front_byte_q <= 3'd0;
			main_front_collision_q <= 1'b0;
			main_read_ahead_valid <= '0;
			for (main_tag_index = 0; main_tag_index < MAIN_CACHE_SETS;
			     main_tag_index = main_tag_index + 1)
				main_read_ahead_tag[main_tag_index] <= '0;
			main_prefetch_line_q <= 28'd0;
			main_prefetch_tag_q <= '0;
			main_prefetch_set_q <= '0;
			main_prefetch_beat <= 4'd0;
			main_prefetch_discard <= 1'b0;
			grom_front_hit_q  <= 1'b0;
			grom_read_ahead_q <= 64'd0;
			grom_read_ahead_valid <= 1'b0;
			grom_read_ahead_tag <= 19'd0;
			grom_prefetch_line_q <= 28'd0;
			grom_prefetch_tag_q <= 19'd0;
			grom_prefetch_beat <= 4'd0;
			grom_prefetch_discard <= 1'b0;
			sound_rdata       <= 8'hff;
			sample_rdata      <= 16'd0;
			vram_rdata        <= 16'd0;
			scan_rdata        <= 64'd0;
		end else begin
			// SOUND hit schedule: synchronous tag/data at T0, compare/extract
			// at T1, register ACK at T2. This fits before the 6809's next Q edge.
			// No hit enters pending_clients or consumes a DDR scheduler turn.
			if (sound_cache_refill) begin
				if (sound_front_refill_way_q)
					sound_cache_valid_way1[op_signature[11:3]] <= sound_cache_publish;
				else
					sound_cache_valid_way0[op_signature[11:3]] <= sound_cache_publish;
			end
			// One metadata write point keeps the replacement decoder narrow. A
			// successful refill and a resident-hit ACK are mutually exclusive.
			if (sound_cache_refill && sound_cache_publish)
				sound_cache_victim[op_signature[11:3]] <=
					!sound_front_refill_way_q;
			else if (sound_cache_hit_touch)
				sound_cache_victim[sound_front_addr_q[11:3]] <=
					!sound_front_hit_way_q;
			if (!sound_miss_pending)
				sound_sample_grants <= 3'd0;
			if (sound_probe_start) begin
				sound_front_addr_q <= sound_addr;
				sound_front_valid_q <= {
					sound_cache_valid_way1[sound_addr[11:3]],
					sound_cache_valid_way0[sound_addr[11:3]]
				};
				sound_front_victim_q <= sound_cache_victim[sound_addr[11:3]];
			end
			if (main_front_cancel) begin
				if (sound_front_state != SF_WAIT_RELEASE || !sound_req)
					sound_front_state <= SF_FREE;
			end else begin
				case (sound_front_state)
					SF_FREE, SF_WAIT_RELEASE: begin
						if (sound_probe_start)
							sound_front_state <= SF_PROBE_RESULT;
						else if (!sound_req)
							sound_front_state <= SF_FREE;
					end
					SF_PROBE_RESULT: begin
						if (!sound_req || sound_addr != sound_front_addr_q) begin
							sound_front_state <= SF_FREE;
						end else begin
							// Way0 wins only the impossible duplicate-tag case; the
							// assertion below keeps that priority from hiding corruption.
							sound_front_data_q <= sound_front_way0_hit
								? sound_front_way0_data : sound_front_way1_data;
							sound_front_hit_q <= sound_front_way0_hit || sound_front_way1_hit;
							sound_front_hit_way_q <= !sound_front_way0_hit &&
								sound_front_way1_hit;
							if (!sound_front_valid_q[0])
								sound_front_refill_way_q <= 1'b0;
							else if (!sound_front_valid_q[1])
								sound_front_refill_way_q <= 1'b1;
							else
								sound_front_refill_way_q <= sound_front_victim_q;
							sound_front_state <= SF_HIT_RESPONSE;
						end
					end
					SF_HIT_RESPONSE: begin
						if (!sound_req || sound_addr != sound_front_addr_q) begin
							sound_front_state <= SF_FREE;
						end else if (sound_front_hit_q) begin
							sound_rdata <= sound_front_data_q;
							sound_ack <= 1'b1;
							served[CLIENT_SOUND] <= 1'b1;
							served_signature[CLIENT_SOUND] <= {20'd0, sound_front_addr_q};
							sound_front_state <= SF_WAIT_RELEASE;
						end else begin
							sound_front_state <= SF_MISS_WAIT;
						end
					end
					SF_MISS_WAIT: begin
						if (!sound_req || sound_addr != sound_front_addr_q)
							sound_front_state <= SF_FREE;
					end
					default: sound_front_state <= SF_FREE;
				endcase
			end
			// The CPU program-ROM cache has one independent, registered owner.
			// Hits never enter the shared scheduler; only MF_MISS_WAIT is visible
			// to pending_clients.  The RAM read remains in this same clocked process
			// as the refill write so Quartus can retain the canonical 1W/1R M10K.
			if (main_probe_enable) begin
				main_read_ahead_q <= main_read_ahead[main_probe_addr[11:3]];
`ifdef VERILATOR
				// Undefined same-word data must never escape the ownership checks.
				if (main_probe_same_word)
					main_read_ahead_q <= 64'hc011_1de5_bad0_cace;
`endif
				main_front_hit_q <= main_read_ahead_valid[main_probe_addr[11:7]] &&
					main_read_ahead_tag[main_probe_addr[11:7]] == main_probe_addr[21:12] &&
					!main_probe_same_set;
				main_front_byte_q <= {main_probe_addr[2], 2'b00};
				main_front_collision_q <= main_probe_same_set;
			end
			if (main_front_cancel) begin
				// Preserve an already-completed signature across a non-reset
				// boundary. Otherwise a still-held request could be accepted twice
				// after the boundary clears.
				if (main_front_state == MF_WAIT_RELEASE) begin
					if (!main_req)
						main_front_state <= MF_FREE;
				end else begin
					main_front_state <= MF_FREE;
				end
			end else begin
				case (main_front_state)
					MF_FREE: begin
						// An accepted burst from a canceled request must drain before
						// the single-outstanding port can capture another signature.
						if (main_probe_start) begin
							main_front_addr_q <= main_addr;
							main_front_state <= MF_HIT_RESPONSE;
						end
					end

					MF_PROBE, MF_REFILL_PROBE: begin
						if (!main_req || main_addr != main_front_addr_q) begin
							main_front_state <= MF_FREE;
						end else begin
							main_front_state <= main_front_state == MF_PROBE
								? MF_HIT_RESPONSE : MF_REFILL_RESPONSE;
						end
					end

					MF_HIT_RESPONSE: begin
						if (!main_req || main_addr != main_front_addr_q) begin
							main_front_state <= MF_FREE;
						end else if (main_front_hit_q &&
							main_read_ahead_valid[main_front_addr_q[11:7]] &&
							main_read_ahead_tag[main_front_addr_q[11:7]] ==
								main_front_addr_q[21:12] &&
							!main_front_collision_q && !main_refill_same_set) begin
							main_rdata <= line_dword_be(main_read_ahead_q,
								main_front_byte_q);
							main_ack <= 1'b1;
							served[CLIENT_MAIN] <= 1'b1;
							served_signature[CLIENT_MAIN] <=
								{17'd0, main_front_addr_q};
							main_front_state <= MF_WAIT_RELEASE;
						end else begin
							// Invalidate before any refill word can be published.
							main_read_ahead_valid[main_front_addr_q[11:7]] <= 1'b0;
							main_front_state <= MF_MISS_WAIT;
						end
					end

					MF_MISS_WAIT: begin
						// The scheduler case below owns refill launch/completion. A
						// producer cancellation suppresses its response; an accepted
						// DDR burst still drains before MF_FREE can accept another.
						if (!main_req || main_addr != main_front_addr_q)
							main_front_state <= MF_FREE;
					end

					MF_REFILL_RESPONSE: begin
						if (!main_req || main_addr != main_front_addr_q) begin
							main_front_state <= MF_FREE;
						end else if (main_front_hit_q &&
							main_read_ahead_valid[main_front_addr_q[11:7]] &&
							main_read_ahead_tag[main_front_addr_q[11:7]] ==
								main_front_addr_q[21:12] &&
							!main_front_collision_q && !main_refill_same_set) begin
							main_rdata <= line_dword_be(main_read_ahead_q,
								main_front_byte_q);
							main_ack <= 1'b1;
							served[CLIENT_MAIN] <= 1'b1;
							served_signature[CLIENT_MAIN] <=
								{17'd0, main_front_addr_q};
							main_front_state <= MF_WAIT_RELEASE;
						end else begin
							// A failed publication/probe is never acknowledged. Retry
							// through the existing miss scheduler using the same signature.
							main_read_ahead_valid[main_front_addr_q[11:7]] <= 1'b0;
							main_front_state <= MF_MISS_WAIT;
						end
					end

					MF_WAIT_RELEASE: begin
						if (!main_req) begin
							main_front_state <= MF_FREE;
						end else if (main_probe_start) begin
							// The main bus normally supplies a one-cycle low gap, but
							// the memory interface also supports changed held-high traffic.
							main_front_addr_q <= main_addr;
							main_front_state <= MF_HIT_RESPONSE;
						end
					end

					default: main_front_state <= MF_FREE;
				endcase
			end

			// GROM resident hit schedule: capture at T0, synchronous RAM/tag probe
			// at T1, local ACK/data during T1..T2, completion at T2. Only a miss
			// waits for shared arbitration. A refill never overlaps a legal probe
			// of this single-line cache; first re-probe is after its final write.
			if (grom_front_cancel) begin
				if (grom_front_state == GF_WAIT_RELEASE) begin
					if (!grom_req) grom_front_state <= GF_FREE;
				end else begin
					grom_front_state <= GF_FREE;
				end
			end else begin
				case (grom_front_state)
					GF_FREE: begin
						if (grom_req && !grom_miss_scheduler_active) begin
							grom_front_addr_q <= grom_addr;
							grom_front_effective_q <= grom_effective_addr;
							grom_front_state <= GF_PROBE;
						end
					end
					GF_PROBE: begin
						if (!grom_req || grom_addr != grom_front_addr_q) begin
							grom_front_state <= GF_FREE;
						end else begin
							grom_read_ahead_q <=
								grom_read_ahead[grom_front_effective_q[6:3]];
							grom_front_hit_q <= grom_read_ahead_valid &&
								grom_read_ahead_tag == grom_front_effective_q[25:7] &&
								!grom_miss_scheduler_active;
							grom_front_state <= GF_RESPONSE;
						end
					end
					GF_RESPONSE: begin
						if (grom_front_hit_q) begin
							served[CLIENT_GROM] <= 1'b1;
							served_signature[CLIENT_GROM] <= {13'd0, grom_front_addr_q};
							grom_front_state <= GF_WAIT_RELEASE;
						end else if (!grom_req || grom_addr != grom_front_addr_q) begin
							grom_front_state <= GF_FREE;
						end else begin
							grom_front_state <= GF_MISS_WAIT;
						end
					end
					GF_MISS_WAIT: begin
						if (!grom_req || grom_addr != grom_front_addr_q)
							grom_front_state <= GF_FREE;
					end
					GF_WAIT_RELEASE: begin
						if (!grom_req) begin
							grom_front_state <= GF_FREE;
						end else if (grom_addr != grom_front_addr_q) begin
							grom_front_addr_q <= grom_addr;
							grom_front_effective_q <= grom_effective_addr;
							grom_front_state <= GF_PROBE;
						end
					end
					default: grom_front_state <= GF_FREE;
				endcase
			end

			// Commit only the registered front, never a live producer payload.
			// Each one-hot bit selects a constant bank/qword; the active drain
			// bank is immutable even while its DDR beat is stalled. On the first
			// collector write, clear masks in that bank only (not RAM data).
			if (vram_buffer_commit) begin
				for (vram_buffer_index = 0; vram_buffer_index < 32;
				     vram_buffer_index = vram_buffer_index + 1) begin
					if (vram_fast_select_q[vram_buffer_index]) begin
						for (vram_byte_index = 0; vram_byte_index < 8;
						     vram_byte_index = vram_byte_index + 1)
							if (vram_fast_be_q[vram_byte_index])
								vram_write_buffer_data[vram_buffer_index]
									[vram_byte_index * 8 +: 8] <=
									vram_fast_data_q[vram_byte_index * 8 +: 8];
						vram_write_buffer_be[vram_buffer_index] <=
							vram_write_buffer_valid
								? vram_write_buffer_be[vram_buffer_index] | vram_fast_be_q
								: vram_fast_be_q;
					end else if (!vram_write_buffer_valid &&
						vram_buffer_index[4] == vram_collect_bank) begin
						vram_write_buffer_be[vram_buffer_index] <= 8'd0;
					end
				end
				if (vram_write_buffer_valid) begin
					if (vram_fast_index_q < vram_write_buffer_first)
						vram_write_buffer_first <= vram_fast_index_q;
					if (vram_fast_index_q > vram_write_buffer_last)
						vram_write_buffer_last <= vram_fast_index_q;
				end else begin
					vram_write_buffer_valid <= 1'b1;
					vram_write_buffer_base <= vram_fast_base_q;
					vram_write_buffer_first <= vram_fast_index_q;
					vram_write_buffer_last <= vram_fast_index_q;
				end
				vram_fast_pending <= 1'b0;
			end

			case (state)
				ST_IDLE: begin
					DDRAM_RD <= 1'b0;
					DDRAM_WE <= 1'b0;

					if (quiesce) begin
						// Persistent loader state is paused, not reset.
					end else if (loader_pending) begin
						op_client    <= CLIENT_LOADER;
						op_write     <= 1'b1;
						op_byte_addr <= {1'b0, loader_addr};
						op_line_addr <= {1'b0, loader_addr[26:3], 3'b000};
						op_wdata     <= 64'd0;
						op_be        <= 8'd0;
						op_wdata[loader_addr[2:1] * 16 +: 16] <= loader_data;
						op_be[loader_addr[2:1] * 2 +: 2] <= 2'b11;
						state <= ST_ISSUE;
					end else if (rom_download_active) begin
						// Ordinary loader writes retain priority above. Fast HPS
						// staging produces no writes here, but runtime clients must
						// remain quiescent until the image is complete.
					end else if (download_ended) begin
						// MAME copies the first 0x80 bytes of program ROM to
						// RAM before releasing reset. Reading it back here works
						// for both ordinary ioctl writes and MiSTer's fast DDR
						// staging path, where no ioctl_wr pulses are produced.
						op_client    <= CLIENT_VECTOR;
						op_write     <= 1'b0;
						op_byte_addr <= {21'd0, vector_line, 3'b000};
						op_line_addr <= {21'd0, vector_line, 3'b000};
						op_wdata     <= 64'd0;
						op_be        <= 8'd0;
						state <= ST_ISSUE;
					end else if (clear_active) begin
						op_client    <= CLIENT_CLEAR;
						op_write     <= 1'b1;
						op_byte_addr <= VRAM_BASE + (28'(clear_line) << 3);
						op_line_addr <= VRAM_BASE + (28'(clear_line) << 3);
						// MAME initializes each 16-bit framebuffer entry to logical
						// 0x00ff. DDR byte lanes hold CPU-visible 16-bit words swapped,
						// matching vram_payload_data and the scanout endian conversion;
						// therefore the raw clear pattern is ff00, not 00ff. The low
						// logical 0xff is transparent and the palette-bank bits stay zero.
						op_wdata     <= 64'hff00_ff00_ff00_ff00;
						op_be        <= 8'hff;
						state <= ST_ISSUE;
					end else if (vram_write_buffer_retry && !main_front_cancel) begin
						// The old drain owns a reset retry. Its bank/count are still
						// intact; replay it before the newer collector can be flushed.
						vram_write_burst_index <= vram_drain_first;
						vram_write_burst_accepted <= 5'd0;
						vram_write_buffer_retry <= 1'b0;
						write_quiesced <= 1'b0;
						DDRAM_ADDR <= physical_word_addr(vram_drain_base +
							{21'd0, vram_drain_first, 3'b000});
						DDRAM_DIN <= vram_write_buffer_data[{vram_drain_bank, vram_drain_first}];
						DDRAM_BE <= vram_write_buffer_be[{vram_drain_bank, vram_drain_first}];
						DDRAM_WE <= 1'b1;
						state <= ST_VRAM_BURST_WRITE;
					end else if (!main_front_cancel && !scan_req &&
						!pending_clients[CLIENT_SAMPLE] && sample_ack && sample_req &&
						response_byte_index[2:1] != 2'd3) begin
						// Preserve the one-edge ACK-consumption grace inside an ES
						// four-word fetch. It cannot repeat while the same ACK is held.
					end else if (!main_front_cancel && !scan_req && sound_miss_pending &&
						(sound_sample_grants == 3'd4 || !pending_clients[CLIENT_SAMPLE])) begin
						// Normally the ES word3 ACK supplies this opening. The quota
						// also bounds wait under legal no-gap/arbitrary sample traffic.
						// One SOUND qword may delay, but never cancel, the held sample.
						op_client <= CLIENT_SOUND;
						rr_client <= next_client(CLIENT_SOUND);
						sound_sample_grants <= 3'd0;
						state <= ST_CAPTURE;
					end else if (!main_front_cancel && !scan_req &&
						pending_clients[CLIENT_SAMPLE]) begin
						// A chain of collector/drain turns must not starve the ES
						// fetcher. Take one registered sample grant between bursts;
						// any already-ACKed front still merges above on this edge.
						// The ACK-consumption grace below keeps the remaining
						// resident words of the same ES fetch ahead of a new drain.
						// Scanout and reset-retry ownership retain priority.
						op_client <= CLIENT_SAMPLE;
						rr_client <= next_client(CLIENT_SAMPLE);
						if (sound_miss_pending && sound_sample_grants != 3'd4)
							sound_sample_grants <= sound_sample_grants + 3'd1;
						state <= ST_CAPTURE;
					end else if (vram_fast_pending) begin
						// The shared merge above retires the old front on this edge;
						// a changed held request may refill it without a throughput gap.
						if (vram_fast_write && !main_front_cancel) begin
							vram_fast_pending <= 1'b1;
							vram_fast_base_q <= live_vram_block_addr;
							vram_fast_index_q <= live_vram_buffer_index;
							vram_fast_select_q <= 32'b1 << {vram_collect_bank, live_vram_buffer_index};
							vram_fast_data_q <= vram_payload_data;
							vram_fast_be_q <= vram_payload_be;
							if (vram_qwrite_req)
								vram_qwrite_ack <= 1'b1;
							else
								vram_ack <= 1'b1;
							served[CLIENT_VRAM] <= 1'b1;
							served_signature[CLIENT_VRAM] <= live_vram_signature;
						end else begin
							vram_fast_pending <= 1'b0;
						end
					end else if (VRAM_WRITE_COMBINE && !main_front_cancel && vram_write_buffer_valid &&
						vram_client_req && (!vram_client_write ||
							live_vram_block_addr != vram_write_buffer_base)) begin
						// Present the first qword and fixed burst address before entering
						// the burst state. WE, data and byte enables then remain stable on
						// every waitrequest cycle; data advances only after acceptance.
						vram_write_burst_index <= vram_write_buffer_first;
						vram_write_burst_count <=
							{1'b0, vram_write_buffer_last} -
							{1'b0, vram_write_buffer_first} + 5'd1;
						vram_write_burst_accepted <= 5'd0;
						vram_write_buffer_retry <= 1'b0;
						vram_drain_valid <= 1'b1;
						vram_drain_bank <= vram_collect_bank;
						vram_drain_base <= vram_write_buffer_base;
						vram_drain_first <= vram_write_buffer_first;
						vram_collect_bank <= !vram_collect_bank;
						vram_write_buffer_valid <= 1'b0;
						write_quiesced <= 1'b0;
						DDRAM_ADDR <= physical_word_addr(vram_write_buffer_base +
							{21'd0, vram_write_buffer_first, 3'b000});
						DDRAM_DIN <= vram_write_buffer_data[{vram_collect_bank, vram_write_buffer_first}];
						DDRAM_BE <= vram_write_buffer_be[{vram_collect_bank, vram_write_buffer_first}];
						DDRAM_WE <= 1'b1;
						state <= ST_VRAM_BURST_WRITE;
					end else if (scan_req) begin
						// Scanout gets a dedicated burst rather than random reads.
						// Capture the qword-aligned linear-window address; the request remains
						// asserted until the bridge accepts the burst command.
						scan_addr_q <= scan_addr;
						state <= ST_SCAN_ISSUE;
					end else if (vram_fast_write && !main_front_cancel) begin
						// A sequential pixel is acknowledged once it is retained in the
						// one-entry boundary register. It merges into the write window on
						// the next edge while a changed request may refill this stage.
						vram_fast_pending <= 1'b1;
						vram_fast_base_q <= live_vram_block_addr;
						vram_fast_index_q <= live_vram_buffer_index;
						vram_fast_select_q <= 32'b1 << {vram_collect_bank, live_vram_buffer_index};
						vram_fast_data_q <= vram_payload_data;
						vram_fast_be_q <= vram_payload_be;
						cache_valid[CLIENT_VRAM] <= 1'b0;
						if (vram_qwrite_req)
							vram_qwrite_ack <= 1'b1;
						else
							vram_ack <= 1'b1;
						served[CLIENT_VRAM] <= 1'b1;
						served_signature[CLIENT_VRAM] <= live_vram_signature;
					end else begin
						// Resident hits consume no scheduler turn. Only the owned
						// main/GROM misses enter the existing registered selector.
						pending_clients_q <= pending_clients;
						state <= ST_SELECT;
					end
				end

				ST_SELECT: begin
					// Scheduler-priority work or a reset/reload boundary discards
					// only the request snapshot. Held producers remain pending and
					// are snapshotted again after the boundary clears.
					if (quiesce || loader_pending || rom_download_active ||
						rom_download_started || rom_download_finished ||
						download_ended || clear_active || scan_req) begin
						state <= ST_IDLE;
					end else if (selected_valid) begin
						rr_client <= next_client(selected_client);
						if (selected_client == CLIENT_GROM) begin
							if (grom_miss_pending) begin
								grom_prefetch_line_q <= GROM_BASE +
									{2'd0, grom_front_effective_q[25:7], 7'd0};
								grom_prefetch_tag_q <= grom_front_effective_q[25:7];
								grom_read_ahead_valid <= 1'b0;
								grom_prefetch_beat <= 4'd0;
								grom_prefetch_discard <= 1'b0;
								state <= ST_GROM_BURST_ISSUE;
							end else begin
								state <= ST_IDLE;
							end
						end else if (selected_client == CLIENT_MAIN) begin
							// Revalidate the live captured miss because the registered
							// pending mask may outlive a producer cancellation by one turn.
							if (main_miss_pending) begin
								main_prefetch_line_q <= MAIN_BASE +
									{6'd0, main_front_addr_q[21:7], 7'd0};
								main_prefetch_tag_q <= main_front_addr_q[21:12];
								main_prefetch_set_q <= main_front_addr_q[11:7];
								main_read_ahead_valid[main_front_addr_q[11:7]] <=
									1'b0;
								main_prefetch_beat <= 4'd0;
								main_prefetch_discard <= 1'b0;
								state <= ST_MAIN_BURST_ISSUE;
							end else begin
								state <= ST_IDLE;
							end
						end else if (selected_client == CLIENT_SOUND) begin
							// A captured pending mask may outlive cancellation. It must
							// never resurrect a completed or replacement SOUND request.
							if (sound_miss_pending) begin
								op_client <= CLIENT_SOUND;
								sound_sample_grants <= 3'd0;
								state <= ST_CAPTURE;
							end else begin
								state <= ST_IDLE;
							end
						end else begin
							// The preserved grant is the sole runtime index used by
							// generic payload capture and cache lookup.
							op_client <= selected_client;
							if (selected_client == CLIENT_SAMPLE && sound_miss_pending &&
								sound_sample_grants != 3'd4)
								sound_sample_grants <= sound_sample_grants + 3'd1;
							state <= ST_CAPTURE;
						end
					end else begin
						state <= ST_IDLE;
					end
				end

				ST_GROM_BURST_ISSUE: begin
					if (quiesce || loader_pending || rom_download_active ||
						rom_download_started || rom_download_finished ||
						download_ended || clear_active) begin
						DDRAM_RD <= 1'b0;
						state <= ST_IDLE;
					end else if (!DDRAM_BUSY) begin
						DDRAM_ADDR <= physical_word_addr(grom_prefetch_line_q);
						DDRAM_DIN <= 64'd0;
						DDRAM_BE <= 8'd0;
						DDRAM_RD <= 1'b1;
						grom_prefetch_beat <= 4'd0;
						grom_prefetch_discard <= 1'b0;
						state <= ST_GROM_BURST_WAIT;
					end
				end

				ST_GROM_BURST_WAIT: begin
					if (!DDRAM_BUSY)
						DDRAM_RD <= 1'b0;
					if (quiesce || rom_download_active || rom_download_started ||
						rom_download_finished || download_ended)
						grom_prefetch_discard <= 1'b1;
					if (DDRAM_DOUT_READY) begin
						grom_read_ahead[grom_prefetch_beat] <= DDRAM_DOUT;
						if (grom_prefetch_beat == 4'd15) begin
							DDRAM_RD <= 1'b0;
							grom_prefetch_beat <= 4'd0;
							if (!(grom_prefetch_discard || quiesce ||
								rom_download_active || rom_download_started ||
								rom_download_finished || download_ended)) begin
								grom_read_ahead_tag <= grom_prefetch_tag_q;
								grom_read_ahead_valid <= 1'b1;
								if (grom_front_state == GF_MISS_WAIT && grom_req &&
									grom_addr == grom_front_addr_q && !grom_front_cancel)
									grom_front_state <= GF_PROBE;
							end
							grom_prefetch_discard <= 1'b0;
							state <= ST_IDLE;
						end else begin
							grom_prefetch_beat <= grom_prefetch_beat + 1'b1;
						end
					end
				end

				ST_MAIN_BURST_ISSUE: begin
					if (quiesce || loader_pending || rom_download_active ||
						rom_download_started || rom_download_finished ||
						download_ended || clear_active ||
						main_front_state != MF_MISS_WAIT || !main_req ||
						main_addr != main_front_addr_q) begin
						DDRAM_RD <= 1'b0;
						state <= ST_IDLE;
					end else if (!DDRAM_BUSY) begin
						DDRAM_ADDR <= physical_word_addr(main_prefetch_line_q);
						DDRAM_DIN <= 64'd0;
						DDRAM_BE <= 8'd0;
						DDRAM_RD <= 1'b1;
						main_prefetch_beat <= 4'd0;
						main_prefetch_discard <= 1'b0;
						state <= ST_MAIN_BURST_WAIT;
					end
				end

				ST_MAIN_BURST_WAIT: begin
					if (!DDRAM_BUSY)
						DDRAM_RD <= 1'b0;
					if (quiesce || rom_download_active || rom_download_started ||
						rom_download_finished || download_ended)
						main_prefetch_discard <= 1'b1;
					if (DDRAM_DOUT_READY) begin
						main_read_ahead[{main_prefetch_set_q, main_prefetch_beat}] <=
							DDRAM_DOUT;
						if (main_prefetch_beat == 4'd15) begin
							DDRAM_RD <= 1'b0;
							main_prefetch_beat <= 4'd0;
							if (!(main_prefetch_discard || quiesce ||
								rom_download_active || rom_download_started ||
								rom_download_finished || download_ended)) begin
								main_read_ahead_tag[main_prefetch_set_q] <=
									main_prefetch_tag_q;
								main_read_ahead_valid[main_prefetch_set_q] <= 1'b1;
								if (main_front_state == MF_MISS_WAIT && main_req &&
									main_addr == main_front_addr_q)
									main_front_state <= MF_REFILL_PROBE;
							end
							main_prefetch_discard <= 1'b0;
							state <= ST_IDLE;
						end else begin
							main_prefetch_beat <= main_prefetch_beat + 1'b1;
						end
					end
				end

				ST_CAPTURE: begin
					// A reset/reload boundary may abandon an unacknowledged
					// grant. The held producer request will be eligible again.
					if (quiesce || rom_download_active || rom_download_started ||
						rom_download_finished || download_ended ||
						(op_client == CLIENT_SOUND &&
						 (main_front_cancel || sound_front_state != SF_MISS_WAIT || !sound_req ||
						  sound_addr != sound_front_addr_q))) begin
						state <= ST_IDLE;
					end else begin
						op_write        <= capture_write;
						op_vram_qwrite <= capture_vram_qwrite;
						op_byte_addr    <= capture_byte_addr;
						op_line_addr    <= capture_line_addr;
						op_signature    <= capture_signature;
						op_cacheable    <= capture_cacheable;
						op_sample_empty <= capture_sample_empty;
						if (capture_write) begin
							op_wdata <= vram_payload_data;
							op_be <= vram_payload_be;
						end else begin
							op_wdata <= 64'd0;
							op_be <= 8'd0;
						end
						state <= ST_DISPATCH;
					end
				end

				ST_DISPATCH: begin
					// Register the cache lookup independently from its result. The
					// producer still holds the request, while this unconditional
					// response prefetch keeps the indexed tag comparison out of every
					// response-register enable. A reload/reset boundary has priority
					// and leaves the producer unacknowledged for a later retry.
					if (quiesce || rom_download_active || rom_download_started ||
						rom_download_finished || download_ended) begin
						state <= ST_IDLE;
					end else if (VRAM_WRITE_COMBINE && op_client == CLIENT_VRAM && op_write &&
						(!vram_write_buffer_valid ||
						 vram_write_buffer_base == {op_line_addr[27:7], 7'b000_0000})) begin
						// Complete the producer handshake once its payload is retained in
						// the existing one-entry boundary stage. The common front merge is
						// the sole writer of the window, keeping the registered client/cache
						// decode out of every buffer-data register enable. A same-row scan
						// still sees vram_fast_pending and cannot pass the later commit/flush.
						vram_fast_pending <= 1'b1;
						vram_fast_base_q <= {op_line_addr[27:7], 7'b000_0000};
						vram_fast_index_q <= op_line_addr[6:3];
						// op_line_addr is already registered by ST_CAPTURE. Decode the
						// retained VRAM index here so unrelated live GROM/RLE address
						// logic cannot reach the write-window selector. This keeps the
						// existing ACK/commit schedule while removing a redundant stage.
						vram_fast_select_q <= 32'b1 << {vram_collect_bank, op_line_addr[6:3]};
						vram_fast_data_q <= op_wdata;
						vram_fast_be_q <= op_be;
						cache_valid[CLIENT_VRAM] <= 1'b0;
						if (op_vram_qwrite)
							vram_qwrite_ack <= 1'b1;
						else
							vram_ack <= 1'b1;
						served[CLIENT_VRAM] <= 1'b1;
						served_signature[CLIENT_VRAM] <= op_signature;
						state <= ST_IDLE;
					end else begin
						cache_lookup_hit <= op_client != CLIENT_SOUND &&
							op_cacheable && cache_valid[op_client] &&
							cache_tag[op_client] == op_line_addr[27:3];
						response_line <= cache_data[op_client];
						response_byte_index <= op_byte_addr[2:0];
						response_clients <= 5'b00001 << op_client;
						response_signature <= op_signature;
						state <= ST_LOOKUP_RESULT;
					end
				end

				ST_LOOKUP_RESULT: begin
					// The lookup hit is now registered. Empty sample banks use the
					// same pre-staged destination/signature but return a zero line;
					// misses retain the operation payload and continue to DDR.
					if (quiesce || rom_download_active || rom_download_started ||
						rom_download_finished || download_ended) begin
						state <= ST_IDLE;
					end else if (op_sample_empty) begin
						response_line <= 64'd0;
						state <= ST_RESPOND;
					end else if (cache_lookup_hit) begin
						state <= ST_RESPOND;
					end else begin
						state <= ST_ISSUE;
					end
				end

				ST_SCAN_ISSUE: begin
					if (quiesce || loader_pending || rom_download_active ||
						rom_download_started || rom_download_finished ||
						download_ended || clear_active || !scan_req) begin
						DDRAM_RD <= 1'b0;
						state <= ST_IDLE;
					end else if (VRAM_WRITE_COMBINE &&
						vram_write_buffer_valid && scan_write_buffer_conflict) begin
						// The scan address is already registered at this boundary. If its
						// Linear scan window overlaps the retained write window, so make
						// that window durable before accepting the scan request. Scanout
						// continues to hold the request, so ST_IDLE will recapture it after
						// this complete idempotent burst retires.
						vram_write_burst_index <= vram_write_buffer_first;
						vram_write_burst_count <=
							{1'b0, vram_write_buffer_last} -
							{1'b0, vram_write_buffer_first} + 5'd1;
						vram_write_burst_accepted <= 5'd0;
						vram_write_buffer_retry <= 1'b0;
						vram_drain_valid <= 1'b1;
						vram_drain_bank <= vram_collect_bank;
						vram_drain_base <= vram_write_buffer_base;
						vram_drain_first <= vram_write_buffer_first;
						vram_collect_bank <= !vram_collect_bank;
						vram_write_buffer_valid <= 1'b0;
						write_quiesced <= 1'b0;
						DDRAM_ADDR <= physical_word_addr(vram_write_buffer_base +
							{21'd0, vram_write_buffer_first, 3'b000});
						DDRAM_DIN <= vram_write_buffer_data[{vram_collect_bank, vram_write_buffer_first}];
						DDRAM_BE <= vram_write_buffer_be[{vram_collect_bank, vram_write_buffer_first}];
						DDRAM_WE <= 1'b1;
						state <= ST_VRAM_BURST_WRITE;
					end else if (!DDRAM_BUSY) begin
						DDRAM_ADDR <= physical_word_addr(VRAM_BASE +
							{7'd0, scan_addr_q, 1'b0});
						DDRAM_DIN <= 64'd0;
						DDRAM_BE <= 8'd0;
						DDRAM_RD <= 1'b1;
						scan_beat <= 7'd0;
						scan_discard <= 1'b0;
						scan_accept <= 1'b1;
						state <= ST_SCAN_WAIT;
					end
				end

				ST_SCAN_WAIT: begin
					if (!DDRAM_BUSY)
						DDRAM_RD <= 1'b0;
					if (quiesce || rom_download_active || rom_download_started ||
						rom_download_finished || download_ended)
						scan_discard <= 1'b1;
					if (DDRAM_DOUT_READY) begin
						if (!(scan_discard || quiesce || rom_download_active ||
							rom_download_started || rom_download_finished ||
							download_ended)) begin
							scan_rdata <= DDRAM_DOUT;
							scan_data_valid <= 1'b1;
								scan_last <= scan_beat == 7'(SCAN_BURST_WORDS - 1);
						end
						if (scan_beat == 7'(SCAN_BURST_WORDS - 1)) begin
							scan_beat <= 7'd0;
							scan_discard <= 1'b0;
							state <= ST_IDLE;
						end else begin
							scan_beat <= scan_beat + 1'b1;
						end
					end
				end

				ST_ISSUE: begin
					if (quiesce) begin
						// No command is asserted in ST_ISSUE yet, so this operation
						// is safe to abandon and will be regenerated after reset.
						DDRAM_RD <= 1'b0;
						DDRAM_WE <= 1'b0;
						state <= ST_IDLE;
					end else if (!DDRAM_BUSY) begin
						DDRAM_ADDR <= physical_word_addr(op_line_addr);
						DDRAM_DIN  <= op_wdata;
						DDRAM_BE   <= op_be;
						if (op_write) begin
							DDRAM_WE <= 1'b1;
							write_quiesced <= 1'b0;
							state <= ST_WAIT_WRITE;
						end else begin
							DDRAM_RD <= 1'b1;
							state <= ST_WAIT_READ;
						end
					end
				end

				ST_WAIT_READ: begin
					if (!DDRAM_BUSY)
						DDRAM_RD <= 1'b0;
					if (DDRAM_DOUT_READY) begin
						DDRAM_RD <= 1'b0;
						if (rom_download_active || rom_download_started ||
							rom_download_finished || discard_inflight ||
							(download_ended && op_client != CLIENT_VECTOR)) begin
							// Any transaction from an older image is discarded at
							// a reload boundary, including an interrupted vector pass.
							if (op_client <= CLIENT_VRAM) begin
								served[op_client] <= 1'b1;
								served_signature[op_client] <= op_signature;
							end
							discard_inflight <= 1'b0;
							state <= ST_IDLE;
						end else if (op_client == CLIENT_VECTOR) begin
							vector_line_data  <= DDRAM_DOUT;
							vector_load_addr  <= {vector_line, 1'b0};
							vector_load_wdata <= line_dword_be(DDRAM_DOUT, 3'd0);
							vector_load_be    <= 4'hf;
							vector_load_we    <= 1'b1;
							state <= ST_VECTOR_SECOND;
						end else begin
							if (op_client != CLIENT_SOUND) begin
								cache_data[op_client] <= DDRAM_DOUT;
								cache_tag[op_client] <= op_line_addr[27:3];
								cache_valid[op_client] <= 1'b1;
							end
							response_line <= DDRAM_DOUT;
							response_byte_index <= op_byte_addr[2:0];
							response_clients <= 5'b00001 << op_client;
							response_signature <= op_signature;
							state <= ST_RESPOND;
						end
					end
				end

				ST_RESPOND: begin
					// The response payload and destination are registered before
					// byte extraction. Suppress an old-image response if a reload
					// or reset boundary arrived during that added pipeline cycle.
					if (quiesce || rom_download_active || rom_download_started ||
						rom_download_finished || download_ended || discard_inflight) begin
						state <= ST_IDLE;
					end else begin
						if (response_clients[CLIENT_SOUND] && !main_front_cancel && sound_req &&
							sound_front_state == SF_MISS_WAIT &&
							{20'd0, sound_front_addr_q} == response_signature &&
							sound_addr == sound_front_addr_q) begin
							sound_rdata <= line_byte(response_line,
								response_byte_index);
							sound_ack <= 1'b1;
							served[CLIENT_SOUND] <= 1'b1;
							served_signature[CLIENT_SOUND] <= response_signature;
							sound_front_state <= SF_WAIT_RELEASE;
						end
						if (response_clients[CLIENT_SAMPLE]) begin
							sample_rdata <= line_word_be(response_line,
								response_byte_index);
							sample_ack <= 1'b1;
							served[CLIENT_SAMPLE] <= 1'b1;
							served_signature[CLIENT_SAMPLE] <= response_signature;
						end
						if (response_clients[CLIENT_VRAM]) begin
							vram_rdata <= line_word_be(response_line,
								response_byte_index);
							if (op_vram_qwrite)
								vram_qwrite_ack <= 1'b1;
							else
								vram_ack <= 1'b1;
							served[CLIENT_VRAM] <= 1'b1;
							served_signature[CLIENT_VRAM] <= response_signature;
						end
						state <= ST_IDLE;
					end
				end

				ST_VECTOR_SECOND: begin
					if (rom_download_active || rom_download_started ||
						rom_download_finished) begin
						state <= ST_IDLE;
					end else begin
						vector_load_addr  <= {vector_line, 1'b1};
						vector_load_wdata <= line_dword_be(vector_line_data, 3'd4);
						vector_load_be    <= 4'hf;
						vector_load_we    <= 1'b1;
						if (vector_line == 4'd15) begin
							state <= ST_VECTOR_FINISH;
						end else begin
							vector_line <= vector_line + 1'b1;
							state <= ST_IDLE;
						end
					end
				end

				// Hold core reset until the consumer has sampled the final
				// registered vector_load_we pulse on this clock edge.
				ST_VECTOR_FINISH: begin
					vector_line <= 4'd0;
					download_ended <= 1'b0;
					if (VRAM_CLEAR_LINES == 0)
						rom_loaded <= 1'b1;
					else
						clear_active <= 1'b1;
					state <= ST_IDLE;
				end

				ST_VRAM_BURST_WRITE: begin
					// Collection is independent of the fixed drain payload. A held
					// scan stops new captures; already-ACKed front data still merges.
					// No acknowledgement depends on DDRAM_BUSY combinationally.
					if (vram_fast_write && !main_front_cancel &&
						!write_quiesced && !scan_req) begin
						vram_fast_pending <= 1'b1;
						vram_fast_base_q <= live_vram_block_addr;
						vram_fast_index_q <= live_vram_buffer_index;
						vram_fast_select_q <= 32'b1 << {vram_collect_bank, live_vram_buffer_index};
						vram_fast_data_q <= vram_payload_data;
						vram_fast_be_q <= vram_payload_be;
						cache_valid[CLIENT_VRAM] <= 1'b0;
						if (vram_qwrite_req)
							vram_qwrite_ack <= 1'b1;
						else
							vram_ack <= 1'b1;
						served[CLIENT_VRAM] <= 1'b1;
						served_signature[CLIENT_VRAM] <= live_vram_signature;
					end
					// Avalon write bursts keep address/count/WE fixed while each
					// accepted beat advances only DIN/BE. If framework RESET reaches
					// the safe terminator, mirror all remaining dummy acceptances and
					// retry the complete idempotent window after quiesce releases.
					if (quiesce)
						write_quiesced <= 1'b1;
					if (!DDRAM_BUSY) begin
						if (vram_write_burst_accepted + 5'd1 ==
							vram_write_burst_count) begin
							DDRAM_WE <= 1'b0;
							vram_write_burst_accepted <= 5'd0;
							cache_valid[CLIENT_VRAM] <= 1'b0;
							if (write_quiesced || quiesce) begin
								write_quiesced <= 1'b0;
								vram_write_buffer_retry <=
									vram_drain_valid &&
									!rom_download_active && !rom_download_started &&
									!rom_download_finished;
							end else begin
								vram_drain_valid <= 1'b0;
								vram_write_buffer_retry <= 1'b0;
							end
							state <= ST_IDLE;
						end else begin
							vram_write_burst_accepted <=
								vram_write_burst_accepted + 5'd1;
							vram_write_burst_index <=
								vram_write_burst_index + 4'd1;
							DDRAM_DIN <= vram_write_buffer_data[
								{vram_drain_bank, (vram_write_burst_index + 4'd1)}];
							DDRAM_BE <= vram_write_buffer_be[
								{vram_drain_bank, (vram_write_burst_index + 4'd1)}];
						end
					end
				end

				ST_WAIT_WRITE: begin
					if (quiesce)
						write_quiesced <= 1'b1;
					if (!DDRAM_BUSY) begin
						DDRAM_WE <= 1'b0;
						discard_inflight <= 1'b0;
						if (write_quiesced || quiesce) begin
							// The terminator may have substituted a zero-BE write.
							// Leave loader_pending and clear progress untouched;
							// a still-live runtime request will be selected again.
							write_quiesced <= 1'b0;
							cache_valid[CLIENT_VRAM] <= 1'b0;
						end else if (op_client == CLIENT_LOADER) begin
							loader_pending <= 1'b0;
						cache_valid <= 5'd0;
						main_read_ahead_valid <= '0;
						end else if (op_client == CLIENT_CLEAR) begin
							if (!(rom_download_active || download_ended ||
								discard_inflight || rom_download_started ||
								rom_download_finished)) begin
								cache_valid[CLIENT_VRAM] <= 1'b0;
								if (clear_line == CLEAR_LAST) begin
									clear_line <= '0;
									clear_active <= 1'b0;
									rom_loaded <= 1'b1;
								end else begin
									clear_line <= clear_line + 1'b1;
								end
							end
						end else begin
							if (op_vram_qwrite)
								vram_qwrite_ack <= 1'b1;
							else
								vram_ack <= 1'b1;
							served[CLIENT_VRAM] <= 1'b1;
							served_signature[CLIENT_VRAM] <= op_signature;
							if (cache_valid[CLIENT_VRAM] &&
								cache_tag[CLIENT_VRAM] == op_line_addr[27:3])
								cache_valid[CLIENT_VRAM] <= 1'b0;
						end
						state <= ST_IDLE;
					end
				end

				default: state <= ST_IDLE;
			endcase

			// A reload boundary is stronger than any completion from the old
			// image. In particular, it can coincide with the last VRAM-clear
			// write (or the zero-clear vector finish) which otherwise sets loaded.
			if (rom_download_started || rom_download_finished) begin
				rom_loaded <= 1'b0;
				vector_line <= 4'd0;
				clear_line <= '0;
				clear_active <= 1'b0;
				cache_valid <= 5'd0;
				sound_cache_valid_way0 <= '0;
				sound_cache_valid_way1 <= '0;
				main_read_ahead_valid <= '0;
				grom_read_ahead_valid <= 1'b0;
				vram_write_buffer_valid <= 1'b0;
				vram_drain_valid <= 1'b0;
				vram_write_buffer_retry <= 1'b0;
				vram_fast_pending <= 1'b0;
				vector_load_we <= 1'b0;
				if (rom_download_started)
					download_ended <= 1'b0;
				else
					download_ended <= 1'b1;
				// These states own no active DDR handshake and can be
				// abandoned immediately. ISSUE/WAIT states drain normally;
				// their completion is discarded above before the new pass.
				if (state == ST_IDLE || state == ST_SELECT ||
					state == ST_MAIN_BURST_ISSUE ||
					state == ST_GROM_BURST_ISSUE ||
					state == ST_CAPTURE ||
					state == ST_DISPATCH || state == ST_LOOKUP_RESULT ||
					state == ST_RESPOND ||
					state == ST_VECTOR_SECOND || state == ST_VECTOR_FINISH ||
					state == ST_SCAN_ISSUE)
					state <= ST_IDLE;
				// Mark only a handshake which will remain outstanding after
				// this boundary. A completion observed on the same edge is
				// already discarded by the state logic above.
				if (state == ST_ISSUE ||
					(state == ST_WAIT_READ && !DDRAM_DOUT_READY) ||
					(state == ST_WAIT_WRITE && DDRAM_BUSY))
					discard_inflight <= 1'b1;
				else
					discard_inflight <= 1'b0;
				if (state == ST_SCAN_WAIT)
					scan_discard <= 1'b1;
				if (state == ST_GROM_BURST_WAIT)
					grom_prefetch_discard <= 1'b1;
				if (state == ST_MAIN_BURST_WAIT)
					main_prefetch_discard <= 1'b1;
			end
		end
	end

`ifdef VERILATOR
	logic sim_sound_ack_q;
	logic sim_sound_ack_authorized_q;
	logic sim_sound_completed_valid;
	logic [18:0] sim_sound_completed_addr;
	always_ff @(posedge clk) begin
		if (reset) begin
			sim_sound_ack_q <= 1'b0;
			sim_sound_ack_authorized_q <= 1'b0;
			sim_sound_completed_valid <= 1'b0;
			sim_sound_completed_addr <= 19'd0;
		end else begin
			sim_sound_ack_q <= sound_ack;
			sim_sound_ack_authorized_q <= !main_front_cancel && sound_req &&
				sound_addr == sound_front_addr_q &&
				((sound_front_state == SF_HIT_RESPONSE && sound_front_hit_q) ||
				 (state == ST_RESPOND && response_clients[CLIENT_SOUND] &&
				  sound_front_state == SF_MISS_WAIT && !discard_inflight &&
				  response_signature == {20'd0, sound_front_addr_q}));
			assert (!(sound_ack && sim_sound_ack_q))
				else $fatal(1, "SOUND ACK lasted more than one carrier clock");
			if (!sound_req || sound_addr != sim_sound_completed_addr)
				sim_sound_completed_valid <= 1'b0;
			if (sound_ack) begin
				assert (sim_sound_ack_authorized_q && sound_front_state == SF_WAIT_RELEASE)
					else $fatal(1, "SOUND ACK lacks matching front ownership");
				if (sound_req) begin
					assert (!(sim_sound_completed_valid &&
						sim_sound_completed_addr == sound_front_addr_q))
						else $fatal(1, "SOUND request signature acknowledged twice");
					sim_sound_completed_valid <= 1'b1;
					sim_sound_completed_addr <= sound_front_addr_q;
				end
			end
			assert (!pending_clients[CLIENT_SOUND] || sound_miss_pending)
				else $fatal(1, "SOUND resident hit reached shared arbitration");
			assert (sound_sample_grants <= 3'd4)
				else $fatal(1, "SOUND sample-grant quota overflowed");
			assert (!(sound_probe_start && sound_cache_refill))
				else $fatal(1, "SOUND synchronous cache read overlaps refill");
			assert (!(sound_cache_refill && sound_cache_hit_touch))
				else $fatal(1, "SOUND cache refill and hit touch overlap");
			if (sound_front_state == SF_PROBE_RESULT && sound_req &&
				sound_addr == sound_front_addr_q)
				assert (!(sound_front_way0_hit && sound_front_way1_hit))
					else $fatal(1, "SOUND duplicate valid tag across cache ways");
			if (sound_probe_start)
				assert (!sound_miss_scheduler_active)
					else $fatal(1, "SOUND probe overlaps owned refill");
		end
	end
	logic sim_grom_ack_q;
	logic sim_grom_completed_valid;
	logic [25:0] sim_grom_completed_addr;
	logic [28:0] held_ddr_addr;
	logic [63:0] held_ddr_din;
	logic [7:0]  held_ddr_be;
	logic        held_vram_burst_valid;
	logic [63:0] held_vram_burst_din;
	logic [7:0]  held_vram_burst_be;
	logic        sim_main_ack_q;
	logic        sim_main_ack_authorized_q;
	logic        sim_main_completed_valid;
	logic [21:0] sim_main_completed_addr;
	logic        sim_main_refill_response_q;
	logic        sim_main_refill_discard_q;
	logic [MAIN_CACHE_SET_BITS-1:0] sim_main_refill_set_q;
	always_ff @(posedge clk) begin
		assert (!(DDRAM_RD && DDRAM_WE))
			else $fatal(1, "DDRAM read and write asserted together");
		if (reset) begin
			sim_grom_ack_q <= 1'b0;
			sim_grom_completed_valid <= 1'b0;
			sim_grom_completed_addr <= 26'd0;
			sim_main_ack_q <= 1'b0;
			sim_main_ack_authorized_q <= 1'b0;
			sim_main_completed_valid <= 1'b0;
			sim_main_completed_addr <= 22'd0;
			sim_main_refill_response_q <= 1'b0;
			sim_main_refill_discard_q <= 1'b0;
			sim_main_refill_set_q <= '0;
		end else begin
			assert (!(grom_ack && sim_grom_ack_q))
				else $fatal(1, "GROM ACK lasted more than one carrier clock");
			sim_grom_ack_q <= grom_ack;
			if (!grom_req || grom_addr != sim_grom_completed_addr)
				sim_grom_completed_valid <= 1'b0;
			if (grom_ack && !grom_front_cancel) begin
				assert (grom_read_ahead_valid && !grom_miss_scheduler_active &&
					grom_read_ahead_tag == grom_front_effective_q[25:7])
					else $fatal(1, "GROM ACK lacks complete matching cache line");
				if (grom_req) begin
					assert (!(sim_grom_completed_valid &&
						sim_grom_completed_addr == grom_front_addr_q))
						else $fatal(1, "GROM request signature acknowledged twice");
					sim_grom_completed_valid <= 1'b1;
					sim_grom_completed_addr <= grom_front_addr_q;
				end
			end
			if (!grom_front_cancel && grom_front_state == GF_PROBE)
				assert (!grom_miss_scheduler_active)
					else $fatal(1, "GROM probe overlaps single-line refill");
			assert (!pending_clients[CLIENT_GROM] || grom_miss_pending)
				else $fatal(1, "resident GROM hit reached shared scheduler");
			if (state == ST_CAPTURE || state == ST_DISPATCH ||
				state == ST_LOOKUP_RESULT || state == ST_RESPOND)
				assert (op_client != CLIENT_GROM && !response_clients[CLIENT_GROM])
					else $fatal(1, "GROM request reached generic response path");
			assert (!(main_ack && sim_main_ack_q))
				else $fatal(1, "main-ROM ACK lasted more than one carrier clock");
			sim_main_ack_q <= main_ack;
			sim_main_ack_authorized_q <= !main_front_cancel && main_req &&
				main_addr == main_front_addr_q &&
				(main_front_state == MF_HIT_RESPONSE ||
				 main_front_state == MF_REFILL_RESPONSE) &&
				main_front_hit_q &&
				main_read_ahead_valid[main_front_addr_q[11:7]] &&
				main_read_ahead_tag[main_front_addr_q[11:7]] ==
					main_front_addr_q[21:12] &&
				!main_front_collision_q && !main_refill_same_set;

			if (!main_req) begin
				sim_main_completed_valid <= 1'b0;
			end else if (sim_main_completed_valid &&
				main_addr != sim_main_completed_addr) begin
				sim_main_completed_valid <= 1'b0;
			end
			if (main_ack) begin
				assert (sim_main_ack_authorized_q &&
					main_front_state == MF_WAIT_RELEASE && main_front_hit_q &&
					main_read_ahead_valid[main_front_addr_q[11:7]] &&
					main_read_ahead_tag[main_front_addr_q[11:7]] ==
						main_front_addr_q[21:12] &&
					!main_front_collision_q && !main_refill_same_set)
					else $fatal(1, "main-ROM ACK lacks matching front-end ownership");
				if (main_req) begin
					assert (!(sim_main_completed_valid &&
						sim_main_completed_addr == main_front_addr_q))
						else $fatal(1,
							"main-ROM request signature acknowledged twice");
					sim_main_completed_valid <= 1'b1;
					sim_main_completed_addr <= main_front_addr_q;
				end else begin
					// Some unit-test producers release at the half-cycle after
					// sampling ACK. The generation edge was authorized above, but
					// no held signature remains to suppress.
					sim_main_completed_valid <= 1'b0;
				end
			end

			if (!main_front_cancel && (main_front_state == MF_PROBE ||
				main_front_state == MF_HIT_RESPONSE ||
				main_front_state == MF_MISS_WAIT ||
				main_front_state == MF_REFILL_PROBE ||
				main_front_state == MF_REFILL_RESPONSE) && main_req) begin
				assert (main_addr == main_front_addr_q)
					else $fatal(1,
						"main-ROM request changed before its ACK/cancel boundary");
			end
			assert (!(main_refill_write &&
				(main_front_state == MF_PROBE ||
				 main_front_state == MF_REFILL_PROBE)))
				else $fatal(1, "legal main-ROM probe overlapped its refill write");
			assert (!pending_clients[CLIENT_MAIN] ||
				(main_front_state == MF_MISS_WAIT && main_miss_pending))
				else $fatal(1, "scheduler saw a main-ROM request without miss ownership");
			if (state == ST_CAPTURE || state == ST_DISPATCH ||
				state == ST_LOOKUP_RESULT || state == ST_RESPOND) begin
				assert (op_client != CLIENT_MAIN &&
					!response_clients[CLIENT_MAIN])
					else $fatal(1, "main-ROM request entered generic response path");
			end
			if (main_front_state == MF_REFILL_RESPONSE && main_req &&
				main_addr == main_front_addr_q && !main_front_collision_q) begin
				assert (main_front_hit_q &&
					main_read_ahead_valid[main_front_addr_q[11:7]] &&
					main_read_ahead_tag[main_front_addr_q[11:7]] ==
						main_front_addr_q[21:12])
					else $fatal(1, "published main-ROM refill did not re-probe as a hit");
			end

			if (sim_main_refill_response_q)
				assert (main_front_state == MF_REFILL_PROBE)
					else $fatal(1, "published live refill did not enter REFILL_PROBE");
			if (sim_main_refill_discard_q)
				assert (!main_read_ahead_valid[sim_main_refill_set_q])
					else $fatal(1, "discarded main-ROM refill published a valid line");
			sim_main_refill_response_q <= state == ST_MAIN_BURST_WAIT &&
				DDRAM_DOUT_READY && main_prefetch_beat == 4'd15 &&
				!(main_prefetch_discard || quiesce || rom_download_active ||
					rom_download_started || rom_download_finished || download_ended) &&
				main_front_state == MF_MISS_WAIT && main_req &&
				main_addr == main_front_addr_q;
			sim_main_refill_discard_q <= state == ST_MAIN_BURST_WAIT &&
				DDRAM_DOUT_READY && main_prefetch_beat == 4'd15 &&
				(main_prefetch_discard || quiesce || rom_download_active ||
					rom_download_started || rom_download_finished || download_ended);
			if (state == ST_MAIN_BURST_WAIT && DDRAM_DOUT_READY &&
				main_prefetch_beat == 4'd15)
				sim_main_refill_set_q <= main_prefetch_set_q;
		end
		if (!reset) begin
			assert (!(vram_req && vram_qwrite_req))
				else $fatal(1, "legacy and gathered VRAM requests overlap");
			if (vram_drain_valid || state == ST_VRAM_BURST_WRITE)
				assert (vram_collect_bank != vram_drain_bank)
					else $fatal(1, "collector aliases immutable drain bank");
			if (vram_write_buffer_retry)
				assert (vram_drain_valid)
					else $fatal(1, "VRAM retry lost its drain owner");
			if (vram_buffer_commit) begin
				assert ($onehot(vram_fast_select_q) && vram_fast_select_q ==
					(32'b1 << {vram_collect_bank, vram_fast_index_q}))
					else $fatal(1, "VRAM front selected a non-collector slot");
				assert (!vram_write_buffer_valid ||
					vram_write_buffer_base == vram_fast_base_q)
					else $fatal(1, "VRAM front crossed a live collector window");
			end
			if (state == ST_SCAN_ISSUE)
				assert (!vram_drain_valid && !vram_fast_pending)
					else $fatal(1, "scan passed retained VRAM ownership");
		end
		if (!reset && scan_req) begin
			assert (scan_addr[1:0] == 2'd0)
				else $fatal(1, "scanline DDR request is not qword aligned");
		end
		if (!reset && (state == ST_SCAN_ISSUE || state == ST_SCAN_WAIT)) begin
			assert (DDRAM_BURSTCNT == 8'(SCAN_BURST_WORDS))
				else $fatal(1, "scanline DDR request lost its configured burst count");
		end
		if (!reset && (state == ST_GROM_BURST_ISSUE ||
			state == ST_GROM_BURST_WAIT || state == ST_MAIN_BURST_ISSUE ||
			state == ST_MAIN_BURST_WAIT)) begin
			assert (DDRAM_BURSTCNT == 8'd16)
				else $fatal(1, "ROM read-ahead request lost its 16-beat burst count");
		end
		if (!reset && state == ST_VRAM_BURST_WRITE) begin
			assert (vram_write_burst_count >= 5'd1 &&
				vram_write_burst_count <= 5'd16 &&
				DDRAM_BURSTCNT == {3'd0, vram_write_burst_count})
				else $fatal(1, "invalid framebuffer write-burst count");
			assert (DDRAM_ADDR == physical_word_addr(vram_drain_base +
				{21'd0, vram_drain_first, 3'b000}))
				else $fatal(1, "framebuffer write-burst address changed");
			// A successful beat may advance immediately after its acceptance
			// edge. Capture the replacement payload on the first stalled cycle,
			// then require it to remain stable for the rest of that stall.
			if (DDRAM_BUSY) begin
				if (!held_vram_burst_valid) begin
					held_vram_burst_valid <= 1'b1;
					held_vram_burst_din <= DDRAM_DIN;
					held_vram_burst_be <= DDRAM_BE;
				end else begin
					assert ({DDRAM_DIN, DDRAM_BE} ==
						{held_vram_burst_din, held_vram_burst_be})
						else $fatal(1, "framebuffer write-burst payload changed while busy");
				end
			end else begin
				held_vram_burst_valid <= 1'b0;
			end
		end else begin
			held_vram_burst_valid <= 1'b0;
		end
		if (!reset && state == ST_CAPTURE) begin
			assert (op_client <= CLIENT_VRAM)
				else $fatal(1, "non-runtime client entered payload capture");
		end
		if (!reset && state == ST_RESPOND) begin
			assert ($onehot(response_clients))
				else $fatal(1, "DDR response destination is not one-hot");
		end
		if (!reset && (state == ST_WAIT_READ || state == ST_WAIT_WRITE) && DDRAM_BUSY) begin
			assert ({DDRAM_ADDR, DDRAM_DIN, DDRAM_BE} ==
				{held_ddr_addr, held_ddr_din, held_ddr_be})
				else $fatal(1, "DDRAM request payload changed while busy");
		end
		if (state == ST_ISSUE && !DDRAM_BUSY) begin
			held_ddr_addr <= physical_word_addr(op_line_addr);
			held_ddr_din  <= op_wdata;
			held_ddr_be   <= op_be;
		end
	end
`endif

endmodule
