// SPDX-License-Identifier: GPL-3.0-or-later
//
// Complete Rev-2 ITech32/SFTM sound-board integration: EF68B09-compatible
// CPU, two main-command latches, ES5506, 8 KiB work RAM, program banking,
// periodic FIRQ, and board-level stereo routing.

`timescale 1ns/1ps

module itech32_sound_board #(
	parameter integer FIRQ_CLOCK_HZ = 16_000_000,
	parameter integer FIRQ_RATE_HZ  = 240,
	parameter integer ES_SLOT_TICKS = 16,
	parameter bit POT_COMPARE_ACTIVE_HIGH = 1'b1,
	parameter bit POT_RES_ACTIVE_HIGH     = 1'b1
) (
	input  logic               clk,
	input  logic               reset,
	input  logic               rev1_mode,
	input  logic               ce_8m,
	input  logic               ce_16m,
	input  logic               ce_2m,

	// Main-CPU command port. MAME accepts every write immediately. If both
	// latches are pending, a new command replaces latch 2 (newest wins).
	input  logic               main_command_valid,
	input  logic [7:0]         main_command,
	output logic               main_command_ready,
	input  logic               main_special_read,
	output logic               sound_special,
	output logic [1:0]         command_pending,

	// Byte-addressed sound-program DDR port.
	output logic               sound_req,
	output logic [18:0]        sound_addr,
	input  logic               sound_ack,
	input  logic [7:0]         sound_rdata,

	// Big-endian 16-bit sample DDR port; sample_addr is a byte address.
	output logic               sample_req,
	output logic [1:0]         sample_bank,
	output logic [21:0]        sample_addr,
	input  logic               sample_ack,
	input  logic [15:0]        sample_rdata,

	// Raw external ES5506 PAR comparator/discharge boundary. Current core
	// integration leaves the analogue RC circuit unpopulated and holds the
	// comparator inactive; polarity remains explicit for future board wiring.
	input  logic               pot_compare_pin_i,
	output logic               pot_res_pin_o,

	output logic signed [15:0] audio_left,
	output logic signed [15:0] audio_right,
	output logic               audio_strobe,

	// Integration/debug status. sound_irq and sound_firq are the actual
	// levels presented to the 6809; ES IRQ is intentionally debug-only.
	output logic               sound_irq,
	output logic               sound_firq,
	output logic               es_irq_debug,
	output logic [7:0]         sound_bank,
	output logic               cpu_mem_valid,
	output logic [15:0]        cpu_addr,
	output logic               cpu_write,
	output logic [7:0]         cpu_wdata,
	output logic [111:0]       cpu_debug_regs
);

	typedef enum logic [1:0] {
		BRIDGE_IDLE,
		BRIDGE_WAIT,
		BRIDGE_RESPONSE,
		BRIDGE_RELEASE
	} bridge_state_t;

	logic [7:0] cpu_rdata;
	logic       cpu_ready;
	logic [7:0] cpu_read_data_next;
	logic       cpu_read_ready_next;
	logic [7:0] cpu_read_response_data_q;
	logic       cpu_read_response_valid_q;
	logic [1:0] cpu_read_response_rearm_q;
	logic       cpu_ce_e;
	logic       cpu_ce_q;
	logic       cpu_ce_2m;
	logic [1:0] cpu_phase;
	logic       cpu_opcode_fetch;
	logic       cpu_opcode_fetch_pre_q;
	logic       cpu_opcode_fetch_q;
	logic       cpu_bus_status;
	logic       cpu_bus_available;
	logic       cpu_busy;
	logic       cpu_lic;
	logic       cpu_bus_valid_pre_q;
	logic [15:0] cpu_bus_addr_pre_q;
	logic       cpu_bus_write_pre_q;
	logic [7:0] cpu_bus_wdata_pre_q;
	logic       cpu_bus_valid_q;
	logic [15:0] cpu_bus_addr_q;
	logic       cpu_bus_write_q;
	logic [7:0] cpu_bus_wdata_q;
	logic [1:0] cpu_bus_rearm_q;

	logic [7:0] command_latch1;
	logic [7:0] command_latch2;
	logic       pending1;
	logic       pending2;

	logic       es_select;
	logic       via_select;
	logic       ram_select;
	logic       rom_select;
	logic       cpu_read_commit;
	logic       cpu_write_commit;
	logic       cpu_cycle_advance;

	bridge_state_t es_bridge_state;
	bridge_state_t ram_bridge_state;
	bridge_state_t rom_bridge_state;

	logic       es_host_req;
	logic       es_host_ack;
	logic [7:0] es_host_rdata;
	logic [7:0] es_response_data;
	logic       es_held_write;
	logic [5:0] es_held_addr;
	logic [7:0] es_held_wdata;

	logic       ram_request;
	logic       ram_response_valid;
	logic [7:0] ram_response_data;
	logic [7:0] ram_held_data;

	logic       mapped_sound_req;
	logic [18:0] mapped_sound_addr;
	logic       bank_valid;
	logic [18:0] rom_held_addr;
	logic [7:0] rom_response_data;

	logic signed [19:0] es_audio_left;
	logic signed [19:0] es_audio_right;
	logic               es_audio_strobe;
	logic [7:0]         es_irq_vector;
	logic [6:0]         es_page;
	logic [4:0]         es_active_voices;
	logic [4:0]         es_scan_voice;
	logic               es_engine_busy;
	logic               sample_companded_unused;
	logic [4:0]         sample_voice_unused;
	logic               par_comparator_tripped;
	logic               par_discharge_active;

	logic [31:0] firq_phase;
	logic periodic_firq;
	logic via_irq;
	logic [7:0] via_rdata;
	localparam logic [31:0] FIRQ_PHASE_LIMIT =
		32'(FIRQ_CLOCK_HZ - FIRQ_RATE_HZ);

	assign main_command_ready = 1'b1;
	assign command_pending = {rev1_mode ? 1'b0 : pending2, pending1};
	assign sound_irq = pending1 | (!rev1_mode && pending2);
	assign sound_firq = rev1_mode ? via_irq : periodic_firq;

	itech32_es5506_par_pins #(
		.POT_COMPARE_ACTIVE_HIGH (POT_COMPARE_ACTIVE_HIGH),
		.POT_RES_ACTIVE_HIGH     (POT_RES_ACTIVE_HIGH)
	) par_pins (
		.clk                  (clk),
		.reset                (reset),
		.pot_compare_pin_i    (pot_compare_pin_i),
		.discharge_active_i   (par_discharge_active),
		.comparator_tripped_o (par_comparator_tripped),
		.pot_res_pin_o        (pot_res_pin_o)
	);

	// The 6809 address and R/W outputs are combinational functions of its
	// instruction state, but remain stable for the complete E/Q bus cycle.
	// Snapshot them at the board boundary before decode so the ready/phase
	// feedback and bridge state inputs do not include the CPU's address cone.
	// The first preserved stage is deliberately payload-only and has no broad
	// decode fanout; the second stage owns all board consumers. The phase machine
	// is held while valid has not crossed both stages, so the extra fabric clock
	// does not change an accepted E/Q edge or architectural commit ordering.
	always_ff @(posedge clk) begin
		if (reset) begin
			cpu_bus_valid_pre_q <= 1'b0;
			cpu_bus_addr_pre_q <= 16'd0;
			cpu_bus_write_pre_q <= 1'b0;
			cpu_bus_wdata_pre_q <= 8'd0;
			cpu_opcode_fetch_pre_q <= 1'b0;
			cpu_bus_valid_q <= 1'b0;
			cpu_bus_addr_q <= 16'd0;
			cpu_bus_write_q <= 1'b0;
			cpu_bus_wdata_q <= 8'd0;
			cpu_opcode_fetch_q <= 1'b0;
			cpu_bus_rearm_q <= 2'b00;
		end else begin
			cpu_bus_valid_pre_q <= cpu_mem_valid;
			if (cpu_mem_valid) begin
				cpu_bus_addr_pre_q <= cpu_addr;
				cpu_bus_write_pre_q <= cpu_write;
				cpu_bus_wdata_pre_q <= cpu_wdata;
				cpu_opcode_fetch_pre_q <= cpu_opcode_fetch;
			end
			if (cpu_bus_valid_pre_q) begin
				cpu_bus_addr_q <= cpu_bus_addr_pre_q;
				cpu_bus_write_q <= cpu_bus_write_pre_q;
				cpu_bus_wdata_q <= cpu_bus_wdata_pre_q;
				cpu_opcode_fetch_q <= cpu_opcode_fetch_pre_q;
			end

			// The 6809 can keep AVMA asserted across adjacent cycles. Suppress the
			// decoded valid level while the newly accepted E edge propagates through
			// both payload stages; otherwise a bridge returning to IDLE could observe
			// and relaunch the just-completed address for one fabric clock.
			if (cpu_cycle_advance) begin
				cpu_bus_valid_q <= 1'b0;
				cpu_bus_rearm_q <= 2'b11;
			end else if (|cpu_bus_rearm_q) begin
				cpu_bus_valid_q <= 1'b0;
				cpu_bus_rearm_q <= {cpu_bus_rearm_q[0], 1'b0};
			end else begin
				cpu_bus_valid_q <= cpu_bus_valid_pre_q;
				cpu_bus_rearm_q <= 2'b00;
			end
		end
	end

	assign es_select = cpu_bus_valid_q &&
	                   (cpu_bus_addr_q[15:8] == 8'h08) &&
	                   !cpu_bus_addr_q[6];
	assign via_select = rev1_mode && cpu_bus_valid_q &&
		(cpu_bus_addr_q[15:4] == 12'h140);
	assign ram_select = cpu_bus_valid_q &&
	                    (cpu_bus_addr_q[15:13] == 3'b001);
	assign rom_select = cpu_bus_valid_q &&
	                    !cpu_bus_write_q &&
	                    (cpu_bus_addr_q[15] ||
	                     ((cpu_bus_addr_q[15:14] == 2'b01) && bank_valid));

	// These remain the actual accepted E/Q edges. Only their payload/decode is
	// taken from the settled snapshot above; no architectural commit is delayed.
	assign cpu_read_commit = cpu_ce_e && cpu_bus_valid_q && cpu_ready &&
	                         !cpu_bus_write_q;
	assign cpu_write_commit = cpu_ce_q && cpu_bus_valid_q && cpu_ready &&
	                          cpu_bus_write_q;
	assign cpu_cycle_advance = cpu_ce_e && cpu_bus_valid_q && cpu_ready;

	// Exact MAME dispatch rule: fill latch 1 if it is empty, otherwise write
	// latch 2 without checking its pending flag. Reads acknowledge only the
	// addressed latch.
	always_ff @(posedge clk) begin
		if (reset) begin
			command_latch1 <= 8'd0;
			command_latch2 <= 8'd0;
			pending1 <= 1'b0;
			pending2 <= 1'b0;
			sound_special <= 1'b0;
		end else begin
			if (cpu_read_commit && !rev1_mode && (cpu_bus_addr_q == 16'h0000))
				pending1 <= 1'b0;
			if (cpu_read_commit && rev1_mode && (cpu_bus_addr_q == 16'h0400))
				pending1 <= 1'b0;
			if (cpu_read_commit && !rev1_mode && (cpu_bus_addr_q == 16'h0400))
				pending2 <= 1'b0;

			if (main_command_valid) begin
				if (rev1_mode) begin
					command_latch1 <= main_command;
					pending1 <= 1'b1;
					pending2 <= 1'b0;
				end else if (pending1) begin
					command_latch2 <= main_command;
					pending2 <= 1'b1;
				end else begin
					command_latch1 <= main_command;
					pending1 <= 1'b1;
				end
			end

			if (main_special_read && pending1)
				sound_special <= ~sound_special;
		end
	end

	// Exact-average 240 Hz level interrupt from the 16 MHz enable. It queues
	// no extra events while high and is cleared only by a committed $1400 write.
	always_ff @(posedge clk) begin
		if (reset) begin
			firq_phase <= 32'd0;
			periodic_firq <= 1'b0;
		end else begin
			if (!rev1_mode && ce_16m) begin
				if (firq_phase >= FIRQ_PHASE_LIMIT) begin
					firq_phase <= firq_phase - FIRQ_PHASE_LIMIT;
					periodic_firq <= 1'b1;
				end else begin
					firq_phase <= firq_phase + 32'(FIRQ_RATE_HZ);
				end
			end
			if (!rev1_mode && cpu_write_commit && (cpu_bus_addr_q == 16'h1400))
				periodic_firq <= 1'b0;
		end
	end

	itech32_sound_cpu sound_cpu (
		.clk                    (clk),
		.reset                  (reset),
		.ce_8m                  (ce_8m),
		.mem_valid              (cpu_mem_valid),
		.mem_addr               (cpu_addr),
		.mem_write              (cpu_write),
		.mem_wdata              (cpu_wdata),
		.mem_rdata              (cpu_rdata),
		.mem_ready              (cpu_ready),
		.irq                    (sound_irq),
		.firq                   (sound_firq),
		.nmi                    (1'b0),
		.ce_e                   (cpu_ce_e),
		.ce_q                   (cpu_ce_q),
		.ce_cpu_2m              (cpu_ce_2m),
		.phase                  (cpu_phase),
		.opcode_fetch           (cpu_opcode_fetch),
		.bus_status             (cpu_bus_status),
		.bus_available          (cpu_bus_available),
		.cpu_busy               (cpu_busy),
		.last_instruction_cycle (cpu_lic),
		.debug_regs             (cpu_debug_regs)
	);

	// ES host bridge. RESPONSE holds ready/data until the 6809 consumes the
	// bus cycle; RELEASE guarantees a request-low interval between accesses.
	assign es_host_req = (es_bridge_state == BRIDGE_WAIT);
	always_ff @(posedge clk) begin
		if (reset) begin
			es_bridge_state <= BRIDGE_IDLE;
			es_response_data <= 8'd0;
			es_held_write <= 1'b0;
			es_held_addr <= 6'd0;
			es_held_wdata <= 8'd0;
		end else begin
			case (es_bridge_state)
				BRIDGE_IDLE: begin
					if (es_select) begin
						es_held_write <= cpu_bus_write_q;
						es_held_addr <= cpu_bus_addr_q[5:0];
						es_held_wdata <= cpu_bus_wdata_q;
						es_bridge_state <= BRIDGE_WAIT;
					end
				end
				BRIDGE_WAIT:
					if (es_host_ack) begin
						es_response_data <= es_host_rdata;
						es_bridge_state <= BRIDGE_RESPONSE;
					end
				BRIDGE_RESPONSE:
					if (cpu_ce_e && cpu_bus_valid_q)
						es_bridge_state <= BRIDGE_RELEASE;
				default:
					es_bridge_state <= BRIDGE_IDLE;
			endcase
		end
	end

	itech32_es5506 #(
		.SLOT_TICKS (ES_SLOT_TICKS)
	) es5506 (
		.clk               (clk),
		.reset             (reset),
		.ce_16m            (ce_16m),
		.host_req          (es_host_req),
		.host_write        (es_held_write),
		.host_addr         (es_held_addr),
		.host_wdata        (es_held_wdata),
		.host_rdata        (es_host_rdata),
		.host_ack          (es_host_ack),
		.par_comparator_tripped (par_comparator_tripped),
		.par_discharge     (par_discharge_active),
		.sample_req        (sample_req),
		.sample_bank       (sample_bank),
		.sample_addr       (sample_addr),
		.sample_companded  (sample_companded_unused),
		.sample_voice      (sample_voice_unused),
		.sample_rdata      (sample_rdata),
		.sample_ack        (sample_ack),
		.audio_left        (es_audio_left),
		.audio_right       (es_audio_right),
		.audio_strobe      (es_audio_strobe),
		.irq               (es_irq_debug),
		.irq_vector        (es_irq_vector),
		.current_page      (es_page),
		.active_voices     (es_active_voices),
		.scan_voice        (es_scan_voice),
		.engine_busy       (es_engine_busy)
	);

	// Registered-read M10K work RAM and its one-shot response bridge.
	assign ram_request = (ram_bridge_state == BRIDGE_IDLE) && ram_select;
	always_ff @(posedge clk) begin
		if (reset) begin
			ram_bridge_state <= BRIDGE_IDLE;
			ram_held_data <= 8'd0;
		end else begin
			case (ram_bridge_state)
				BRIDGE_IDLE:
					if (ram_select)
						ram_bridge_state <= BRIDGE_WAIT;
				BRIDGE_WAIT:
					if (ram_response_valid) begin
						ram_held_data <= ram_response_data;
						ram_bridge_state <= BRIDGE_RESPONSE;
					end
				BRIDGE_RESPONSE:
					if (cpu_ce_e && cpu_bus_valid_q)
						ram_bridge_state <= BRIDGE_RELEASE;
				default:
					ram_bridge_state <= BRIDGE_IDLE;
			endcase
		end
	end

	itech32_sound_ram work_ram (
		.clk            (clk),
		.reset          (reset),
		.request        (ram_request),
		.write          (cpu_bus_write_q),
		.addr           (cpu_bus_addr_q[12:0]),
		.wdata          (cpu_bus_wdata_q),
		.response_valid (ram_response_valid),
		.rdata          (ram_response_data)
	);

	// Program-ROM map and a request/response bridge which tolerates one-cycle
	// DDR acknowledgements at arbitrary 6809 phase alignment.
	itech32_sound_rom_map rom_map (
		.clk        (clk),
		.reset      (reset),
		.rev1_mode  (rev1_mode),
		.cpu_commit (cpu_write_commit),
		.cpu_valid  (cpu_bus_valid_q && !reset),
		.cpu_addr   (cpu_bus_addr_q),
		.cpu_write  (cpu_bus_write_q),
		.cpu_wdata  (cpu_bus_wdata_q),
		.sound_bank (sound_bank),
		.sound_req  (mapped_sound_req),
		.sound_addr (mapped_sound_addr),
		.bank_valid (bank_valid)
	);

	itech32_via6522 via6522 (
		.clk(clk), .reset(reset), .ce_2m(ce_2m),
		.read_commit(cpu_read_commit && via_select),
		.write_commit(cpu_write_commit && via_select),
		.addr(cpu_bus_addr_q[3:0]), .wdata(cpu_bus_wdata_q),
		.rdata(via_rdata), .irq(via_irq)
	);

	assign sound_req = (rom_bridge_state == BRIDGE_WAIT);
	assign sound_addr = rom_held_addr;
	always_ff @(posedge clk) begin
		if (reset) begin
			rom_bridge_state <= BRIDGE_IDLE;
			rom_held_addr <= 19'd0;
			rom_response_data <= 8'd0;
		end else begin
			case (rom_bridge_state)
				BRIDGE_IDLE: begin
					if (mapped_sound_req) begin
						rom_held_addr <= mapped_sound_addr;
						rom_bridge_state <= BRIDGE_WAIT;
					end
				end
				BRIDGE_WAIT: begin
					if (sound_ack) begin
						rom_response_data <= sound_rdata;
						rom_bridge_state <= BRIDGE_RESPONSE;
					end
				end
				BRIDGE_RESPONSE:
					if (cpu_ce_e && cpu_bus_valid_q)
						rom_bridge_state <= BRIDGE_RELEASE;
				default:
					rom_bridge_state <= BRIDGE_IDLE;
			endcase
		end
	end

	// Byte-wide 6809 map. Unmapped reads return $ff and complete immediately.
	// This first stage is deliberately kept outside the CPU return path: it
	// resolves the local decode or waits for a bridge response, then the result
	// is captured below before ready is exposed to the 6809.
	always_comb begin
		cpu_read_data_next = 8'hff;
		// Hold the reset-vector cycle for the single clock needed to seed the
		// registered bus snapshot. mem_valid itself is already a CPU-boundary FF.
		cpu_read_ready_next = !cpu_mem_valid || cpu_bus_valid_q;

		if (es_select) begin
			cpu_read_data_next = es_response_data;
			cpu_read_ready_next = (es_bridge_state == BRIDGE_RESPONSE);
		end else if (ram_select) begin
			cpu_read_data_next = ram_held_data;
			cpu_read_ready_next = (ram_bridge_state == BRIDGE_RESPONSE);
		end else if (rom_select) begin
			cpu_read_data_next = rom_response_data;
			cpu_read_ready_next = (rom_bridge_state == BRIDGE_RESPONSE);
		end else if (via_select) begin
			cpu_read_data_next = via_rdata;
		end else if (!cpu_bus_write_q) begin
			case (cpu_bus_addr_q)
				16'h0000: if (!rev1_mode) cpu_read_data_next = command_latch1;
				16'h0400: cpu_read_data_next = rev1_mode ? command_latch1 :
					command_latch2;
				16'h1800: if (!rev1_mode)
					cpu_read_data_next = {pending1, 7'd0};
				default: begin
					// Invalid SFTM banks are deliberately open-bus/zero and do
					// not access beyond the packaged 0x48000-byte image.
					if ((cpu_bus_addr_q[15:14] == 2'b01) && !bank_valid)
						cpu_read_data_next = 8'h00;
				end
			endcase
		end
	end

	// Register every read response before allowing the next E edge. This is a
	// one-entry response buffer: the phase generator remains held while empty,
	// so even an immediately-ready local read cannot be consumed on the edge
	// that captures it. Writes retain the original direct ready path and exact
	// Q-edge commit semantics.
	always_ff @(posedge clk) begin
		if (reset) begin
			cpu_read_response_data_q <= 8'hff;
			cpu_read_response_valid_q <= 1'b0;
			cpu_read_response_rearm_q <= 2'b00;
		end else if (!cpu_mem_valid || !cpu_bus_valid_q || cpu_bus_write_q) begin
			cpu_read_response_valid_q <= 1'b0;
			cpu_read_response_rearm_q <= 2'b00;
		end else if (cpu_read_commit) begin
			cpu_read_response_valid_q <= 1'b0;
			cpu_read_response_rearm_q <= 2'b11;
		end else if (|cpu_read_response_rearm_q) begin
			// cpu_addr changes as a consequence of the accepted E edge. Allow
			// both board snapshot stages to capture that next address before
			// arming a response for a back-to-back read.
			cpu_read_response_valid_q <= 1'b0;
			cpu_read_response_rearm_q <= {cpu_read_response_rearm_q[0], 1'b0};
		end else if (!cpu_read_response_valid_q && cpu_read_ready_next) begin
			cpu_read_response_data_q <= cpu_read_data_next;
			cpu_read_response_valid_q <= 1'b1;
			cpu_read_response_rearm_q <= 2'b00;
		end
	end

	always_comb begin
		cpu_rdata = cpu_read_response_data_q;
		if (!cpu_mem_valid)
			cpu_ready = 1'b1;
		else if (!cpu_bus_valid_q)
			cpu_ready = 1'b0;
		else if (cpu_bus_write_q)
			cpu_ready = cpu_read_ready_next;
		else
			cpu_ready = cpu_read_response_valid_q;
	end

	itech32_sound_output board_output (
		.es_left      (es_audio_left),
		.es_right     (es_audio_right),
		.es_strobe    (es_audio_strobe),
		.audio_left   (audio_left),
		.audio_right  (audio_right),
		.audio_strobe (audio_strobe)
	);

endmodule
