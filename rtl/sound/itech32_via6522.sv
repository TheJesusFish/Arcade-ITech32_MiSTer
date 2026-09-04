// SPDX-License-Identifier: GPL-2.0-or-later
// MOS 6522 subset used by the ITech32 Rev-1 sound board. Timer/IFR/IER and
// port register behavior are architectural; external cabinet outputs are not.
`timescale 1ns/1ps

module itech32_via6522 (
	input  logic       clk,
	input  logic       reset,
	input  logic       ce_2m,
	input  logic       read_commit,
	input  logic       write_commit,
	input  logic [3:0] addr,
	input  logic [7:0] wdata,
	output logic [7:0] rdata,
	output logic       irq
);
	logic [7:0] orb, ora, ddrb, ddra;
	logic [7:0] acr, pcr, sr;
	logic [6:0] ifr, ier;
	logic [15:0] timer1_counter, timer1_latch;
	logic [15:0] timer2_counter, timer2_latch;
	logic timer1_running, timer2_running;

	assign irq = |(ifr & ier);

	always_comb begin
		case (addr)
			4'h0: rdata = orb;
			4'h1: rdata = ora;
			4'h2: rdata = ddrb;
			4'h3: rdata = ddra;
			4'h4: rdata = timer1_counter[7:0];
			4'h5: rdata = timer1_counter[15:8];
			4'h6: rdata = timer1_latch[7:0];
			4'h7: rdata = timer1_latch[15:8];
			4'h8: rdata = timer2_counter[7:0];
			4'h9: rdata = timer2_counter[15:8];
			4'ha: rdata = sr;
			4'hb: rdata = acr;
			4'hc: rdata = pcr;
			4'hd: rdata = {irq, ifr};
			4'he: rdata = {1'b1, ier};
			default: rdata = ora;
		endcase
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			orb <= 8'd0;
			ora <= 8'd0;
			ddrb <= 8'd0;
			ddra <= 8'd0;
			acr <= 8'd0;
			pcr <= 8'd0;
			sr <= 8'd0;
			ifr <= 7'd0;
			ier <= 7'd0;
			timer1_counter <= 16'hffff;
			timer1_latch <= 16'hffff;
			timer2_counter <= 16'hffff;
			timer2_latch <= 16'hffff;
			timer1_running <= 1'b0;
			timer2_running <= 1'b0;
		end else begin
			if (ce_2m) begin
				if (timer1_running) begin
					if (timer1_counter == 16'd0) begin
						ifr[6] <= 1'b1;
						if (acr[6])
							timer1_counter <= timer1_latch;
						else
							timer1_running <= 1'b0;
					end else begin
						timer1_counter <= timer1_counter - 1'b1;
					end
				end
				if (timer2_running && !acr[5]) begin
					if (timer2_counter == 16'd0) begin
						ifr[5] <= 1'b1;
						timer2_running <= 1'b0;
					end else begin
						timer2_counter <= timer2_counter - 1'b1;
					end
				end
			end

			if (read_commit) begin
				if (addr == 4'h4)
					ifr[6] <= 1'b0;
				if (addr == 4'h8)
					ifr[5] <= 1'b0;
			end

			if (write_commit) begin
				case (addr)
					4'h0: orb <= wdata;
					4'h1, 4'hf: ora <= wdata;
					4'h2: ddrb <= wdata;
					4'h3: ddra <= wdata;
					4'h4, 4'h6: timer1_latch[7:0] <= wdata;
					4'h5: begin
						timer1_latch[15:8] <= wdata;
						timer1_counter <= {wdata, timer1_latch[7:0]};
						timer1_running <= 1'b1;
						ifr[6] <= 1'b0;
					end
					4'h7: timer1_latch[15:8] <= wdata;
					4'h8: timer2_latch[7:0] <= wdata;
					4'h9: begin
						timer2_latch[15:8] <= wdata;
						timer2_counter <= {wdata, timer2_latch[7:0]};
						timer2_running <= 1'b1;
						ifr[5] <= 1'b0;
					end
					4'ha: sr <= wdata;
					4'hb: acr <= wdata;
					4'hc: pcr <= wdata;
					4'hd: ifr <= ifr & ~wdata[6:0];
					4'he: begin
						if (wdata[7])
							ier <= ier | wdata[6:0];
						else
							ier <= ier & ~wdata[6:0];
					end
					default: begin end
				endcase
			end
		end
	end
endmodule
