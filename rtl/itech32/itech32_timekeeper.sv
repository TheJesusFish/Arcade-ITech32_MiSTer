// SPDX-License-Identifier: GPL-3.0-or-later
// M48T02 timekeeper clock registers, after MAME 0.288 timekpr.cpp.
//
// The tournament boards map the chip's 2 KiB at 0x681000, one byte per CPU
// address. Its first 0x7f8 bytes are plain battery RAM (held with the board's
// NVRAM); this block is the last eight: control, seconds, minutes, hours,
// day of week, date, month and year, all BCD. The CPU sees these "visible"
// bytes. Internal counters advance once per second unless the seconds
// register's ST bit stops the oscillator or control bit W (write) is set, and
// are copied to the visible bytes after each tick unless control bit R (read)
// freezes them. Clearing W loads the counters from the visible bytes; leaving
// R copies the counters back.
//
// MAME starts the counters from the host clock. Here they follow the MiSTer
// RTC (hps_io's MSM6242B-layout RTC, sent at core start and once a minute)
// from each game load until the game first sets W to write its own time.
// MAME's masked increment steps the day of week from 7 to 0; the chip, and
// this block, count 1-7.
`timescale 1ns/1ps

module itech32_timekeeper #(
	parameter int CLK_HZ = 47_727_273
) (
	input  logic        clk,
	input  logic        reset,
	// One clock at each MRA load: restart from the MiSTer RTC.
	input  logic        new_game,
	// hps_io RTC: [7:0] seconds, [15:8] minutes, [23:16] hours, [31:24] date,
	// [39:32] month, [47:40] year (BCD), [55:48] day of week 0-6 (Sunday 0),
	// [64] toggles per update.
	input  logic [64:0] rtc,
	// Byte i is offset 0x7f8 + i.
	input  logic [7:0]  write_enable,
	input  logic [63:0] write_data,
	output logic [63:0] read_data
);
	// Bit 7 of control is W, bit 6 R; bit 7 of seconds is ST.
	localparam int BIT_W = 7, BIT_R = 6, BIT_ST = 7;
	localparam int CONTROL = 0, SECONDS = 1, MINUTES = 2, HOURS = 3, DAY = 4,
		DATE = 5, MONTH = 6, YEAR = 7;

	localparam int SECOND_CYCLES = CLK_HZ;
	localparam int SECOND_W = $clog2(SECOND_CYCLES);
	localparam logic [31:0] SECOND_LAST = SECOND_CYCLES - 1;

	logic [7:0] visible_q [8];
	logic [7:0] count_q [8];   // count_q[CONTROL] is MAME's m_control
	logic [SECOND_W-1:0] prescale_q = '0;
	logic rtc_toggle_q = 1'b0;
	logic follow_rtc_q = 1'b1;
	// A second that lands on a CPU write or RTC load waits one clock.
	logic tick_pending_q = 1'b0;

	// MAME time_helper::inc_bcd: the field's masked bits count in BCD and
	// wrap from above max to min (the carry); the unmasked bits are kept.
	function automatic logic [8:0] inc_bcd(input logic [7:0] value,
		input logic [7:0] mask, input logic [7:0] min, input logic [7:0] max);
		logic [7:0] bcd;
		logic carry;
		begin
			bcd = (value + 8'd1) & mask;
			if (bcd[3:0] > 4'd9)
				bcd = {bcd[7:4], 4'd0} + 8'h10;
			carry = bcd > max;
			if (carry)
				bcd = min;
			inc_bcd = {carry, (value & ~mask) | (bcd & mask)};
		end
	endfunction

	function automatic logic [7:0] to_bcd(input logic [7:0] value);
		to_bcd = {value[3:0] / 4'd10, value[3:0] % 4'd10};
	endfunction

	// One second's step of every counter; the carries are each field's own,
	// so the chain is an AND of flags rather than a ripple of increments.
	logic [8:0] sec_n, min_n, hour_n, day_n, date_n, month_n, year_n;
	logic [7:0] max_date;
	logic [7:0] tick_count [8];
	always_comb begin
		// MAME: February has 29 days when the BCD year is divisible by four.
		case (count_q[MONTH] & 8'h1f)
			8'h02: max_date = (((count_q[YEAR][7:4] * 4'd10) + count_q[YEAR][3:0]) % 4 == 0) ?
				8'h29 : 8'h28;
			8'h04, 8'h06, 8'h09, 8'h11: max_date = 8'h30;
			default: max_date = 8'h31;
		endcase
		sec_n   = inc_bcd(count_q[SECONDS], 8'h7f, 8'h00, 8'h59);
		min_n   = inc_bcd(count_q[MINUTES], 8'h7f, 8'h00, 8'h59);
		hour_n  = inc_bcd(count_q[HOURS],   8'h3f, 8'h00, 8'h23);
		// MAME's masked step takes the day from 7 to 0; the chip counts 1-7.
		day_n   = {1'b0, count_q[DAY][7:3],
			count_q[DAY][2:0] == 3'd7 ? 3'd1 : count_q[DAY][2:0] + 3'd1};
		date_n  = inc_bcd(count_q[DATE],    8'h3f, 8'h01, max_date);
		month_n = inc_bcd(count_q[MONTH],   8'h1f, 8'h01, 8'h12);
		year_n  = inc_bcd(count_q[YEAR],    8'hff, 8'h00, 8'h99);
		tick_count = count_q;
		tick_count[SECONDS] = sec_n[7:0];
		if (sec_n[8]) tick_count[MINUTES] = min_n[7:0];
		if (sec_n[8] && min_n[8]) tick_count[HOURS] = hour_n[7:0];
		if (sec_n[8] && min_n[8] && hour_n[8]) begin
			tick_count[DAY] = day_n[7:0];
			tick_count[DATE] = date_n[7:0];
		end
		if (sec_n[8] && min_n[8] && hour_n[8] && date_n[8])
			tick_count[MONTH] = month_n[7:0];
		if (sec_n[8] && min_n[8] && hour_n[8] && date_n[8] && month_n[8])
			tick_count[YEAR] = year_n[7:0];
	end

	wire second = prescale_q == SECOND_LAST[SECOND_W-1:0];
	wire rtc_event = rtc[64] != rtc_toggle_q;
	// A CPU write in the same clock wins; the next minute's update follows.
	wire follow_rtc = rtc_event && follow_rtc_q && !count_q[CONTROL][BIT_W] &&
		write_enable == 8'h00;
	wire load_rtc = new_game || follow_rtc;
	wire control_write = write_enable[CONTROL];
	wire [7:0] control_data = write_data[7:0];

	always_ff @(posedge clk) begin
		rtc_toggle_q <= rtc[64];
		prescale_q <= (second || load_rtc) ? '0 : prescale_q + 1'b1;
		tick_pending_q <= (second || tick_pending_q) && write_enable != 8'h00 && !load_rtc;
		if (reset) begin
			for (int i = 0; i < 8; i++) begin
				visible_q[i] <= 8'hff;
				count_q[i] <= 8'h00;
			end
			follow_rtc_q <= 1'b1;
		end else if (load_rtc) begin
			// rtc_clock_updated, then counters_to_ram unless R freezes them.
			count_q[SECONDS] <= rtc[7:0];
			count_q[MINUTES] <= rtc[15:8];
			count_q[HOURS]   <= rtc[23:16];
			count_q[DAY]     <= to_bcd(rtc[55:48] + 8'd1);
			count_q[DATE]    <= rtc[31:24];
			count_q[MONTH]   <= rtc[39:32];
			count_q[YEAR]    <= rtc[47:40];
			if (new_game) begin
				count_q[CONTROL] <= 8'h00;
				follow_rtc_q <= 1'b1;
			end
			if (new_game || !count_q[CONTROL][BIT_R]) begin
				visible_q[CONTROL] <= new_game ? 8'h00 : count_q[CONTROL];
				visible_q[SECONDS] <= rtc[7:0];
				visible_q[MINUTES] <= rtc[15:8];
				visible_q[HOURS]   <= rtc[23:16];
				visible_q[DAY]     <= to_bcd(rtc[55:48] + 8'd1);
				visible_q[DATE]    <= rtc[31:24];
				visible_q[MONTH]   <= rtc[39:32];
				visible_q[YEAR]    <= rtc[47:40];
			end
		end else if (write_enable != 8'h00) begin
			// timekeeper_device::write. MAME takes a dword's bytes in offset
			// order, so a control write acts before the other bytes land.
			if (control_write) begin
				if (count_q[CONTROL][BIT_W] && !control_data[BIT_W]) begin
					// counters_from_ram (its control byte is then replaced).
					for (int i = 1; i < 8; i++)
						count_q[i] <= visible_q[i];
				end else if (count_q[CONTROL][BIT_R] && !control_data[BIT_W]) begin
					// counters_to_ram
					for (int i = 1; i < 8; i++)
						visible_q[i] <= count_q[i];
				end
				count_q[CONTROL] <= control_data;
				// Setting W writes the game's own time: stop following the RTC.
				if (control_data[BIT_W])
					follow_rtc_q <= 1'b0;
			end
			for (int i = 0; i < 8; i++)
				if (write_enable[i])
					visible_q[i] <= write_data[8 * i +: 8];
		end else if ((second || tick_pending_q) && !count_q[SECONDS][BIT_ST] &&
			!count_q[CONTROL][BIT_W]) begin
			// timer_tick
			for (int i = 1; i < 8; i++)
				count_q[i] <= tick_count[i];
			if (!count_q[CONTROL][BIT_R])
				for (int i = 0; i < 8; i++)
					visible_q[i] <= tick_count[i];
		end
	end

	always_comb
		for (int i = 0; i < 8; i++)
			read_data[8 * i +: 8] = visible_q[i];
endmodule
