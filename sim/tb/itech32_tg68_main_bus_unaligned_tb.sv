`timescale 1ns/1ps

// End-to-end authored 68EC020 odd-longword check through the production TG68
// adapter, SFTM decoder, retained ROM response, and work RAM.  ModelSim is used
// because the production TG68K.C source is VHDL; no game ROM bytes are present.
module itech32_tg68_main_bus_unaligned_tb;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic vector_load_we = 1'b0;
	logic [4:0] vector_load_addr = 5'd0;
	logic [31:0] vector_load_wdata = 32'd0;
	logic [3:0] vector_load_be = 4'd0;
	logic cpu_req, cpu_we, cpu_ack;
	logic [23:0] cpu_addr;
	logic [31:0] cpu_wdata, cpu_rdata;
	logic [3:0] cpu_be;
	logic rom_req, rom_ack;
	logic [21:0] rom_addr;
	logic [31:0] rom_rdata;
	logic [31:0] debug_addr;
	logic [1:0] debug_busstate;
	logic [7:0] rom [0:16'h07ff];
	integer cycles = 0;
	integer rom_reads = 0;

	always #5 clk = ~clk;
	assign rom_ack = rom_req;
	always_comb begin
		rom_rdata = {
			rom[{rom_addr[15:2], 2'b00}], rom[{rom_addr[15:2], 2'b01}],
			rom[{rom_addr[15:2], 2'b10}], rom[{rom_addr[15:2], 2'b11}]
		};
	end
	always @(posedge clk) begin
		cycles <= cycles + 1;
		if (rom_req && rom_ack) begin
			rom_reads <= rom_reads + 1;
			$display("MAIN_ROM addr=%06x data=%08x", rom_addr, rom_rdata);
		end
		if (cycles > 30000)
			$fatal(1, "TG68/main-bus unaligned program timed out pc=%08x", debug_addr);
	end

	itech32_tg68_cpu cpu (
		.clk(clk), .reset(reset), .cpu_68000(1'b0), .cpu_ce(1'b1),
		.irq_level(3'd0), .vector_load_we(vector_load_we),
		.vector_load_addr(vector_load_addr), .vector_load_wdata(vector_load_wdata),
		.vector_load_be(vector_load_be), .board_req(cpu_req), .board_we(cpu_we),
		.board_addr(cpu_addr), .board_wdata(cpu_wdata), .board_be(cpu_be),
		.board_ack(cpu_ack), .board_rdata(cpu_rdata), .debug_addr(debug_addr),
		.debug_busstate(debug_busstate), .debug_nwr(), .debug_nuds(),
		.debug_nlds(), .debug_fc()
	);

	/* verilator lint_off PINCONNECTEMPTY */
	itech32_main_bus bus (
		.clk(clk), .reset(reset), .timekill_mode(1'b0), .bloodstorm_mode(1'b0),
		.rom_buffer_invalidate(1'b0), .cpu_req(cpu_req), .cpu_we(cpu_we),
		.cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_be(cpu_be),
		.cpu_ack(cpu_ack), .cpu_rdata(cpu_rdata), .input_p1(32'd0),
		.input_p2(32'd0), .input_p3(32'd0), .input_p4(32'd0),
		.input_dips(32'd0), .input_extra(32'd0), .protection_address(15'h7a66),
		.nvram_host_access(1'b0), .nvram_host_write(1'b0),
		.nvram_host_addr(17'd0), .nvram_host_wdata(16'd0),
		.nvram_host_rdata(), .nvram_cpu_write(), .video_req(), .video_we(),
		.video_addr(), .video_wdata(), .video_be(), .video_ack(1'b0),
		.video_rdata(16'd0), .rom_req(rom_req), .rom_addr(rom_addr),
		.rom_ack(rom_ack), .rom_rdata(rom_rdata), .sound_command_valid(),
		.sound_command(), .watchdog_strobe(), .vint_ack_strobe(),
		.special_read_strobe(), .color0_strobe(), .color1_strobe(),
		.color_data(), .plane_enable(), .grom_bank(),
		.palette_video_addr(15'd0), .palette_video_rgb()
	);
	/* verilator lint_on PINCONNECTEMPTY */

	task automatic load_vector(input logic [4:0] index, input logic [31:0] value);
		begin
			@(negedge clk);
			vector_load_addr = index;
			vector_load_wdata = value;
			vector_load_be = 4'hf;
			vector_load_we = 1'b1;
			@(negedge clk);
			vector_load_we = 1'b0;
		end
	endtask

	initial begin
		for (integer i = 0; i < 16'h0800; i = i + 1) rom[i] = 8'h00;
		// 0x800100: movea.l #$00800300,A0
		rom[16'h0100]=8'h20; rom[16'h0101]=8'h7c;
		rom[16'h0102]=8'h00; rom[16'h0103]=8'h80;
		rom[16'h0104]=8'h03; rom[16'h0105]=8'h00;
		// move.l (-$1,A0),D0
		rom[16'h0106]=8'h20; rom[16'h0107]=8'h28;
		rom[16'h0108]=8'hff; rom[16'h0109]=8'hff;
		// move.l D0,$00000400.l
		rom[16'h010a]=8'h23; rom[16'h010b]=8'hc0;
		rom[16'h010c]=8'h00; rom[16'h010d]=8'h00;
		rom[16'h010e]=8'h04; rom[16'h010f]=8'h00;
		// move.b #$5a,$00007a66.l
		rom[16'h0110]=8'h13; rom[16'h0111]=8'hfc;
		rom[16'h0112]=8'h00; rom[16'h0113]=8'h5a;
		rom[16'h0114]=8'h00; rom[16'h0115]=8'h00;
		rom[16'h0116]=8'h7a; rom[16'h0117]=8'h66;
		// move.b $00680002.l,D0
		rom[16'h0118]=8'h10; rom[16'h0119]=8'h39;
		rom[16'h011a]=8'h00; rom[16'h011b]=8'h68;
		rom[16'h011c]=8'h00; rom[16'h011d]=8'h02;
		// move.b D0,$00000404.l; bra.s *
		rom[16'h011e]=8'h13; rom[16'h011f]=8'hc0;
		rom[16'h0120]=8'h00; rom[16'h0121]=8'h00;
		rom[16'h0122]=8'h04; rom[16'h0123]=8'h04;
		rom[16'h0124]=8'h60; rom[16'h0125]=8'hfe;
		rom[16'h02ff]=8'h11; rom[16'h0300]=8'h22;
		rom[16'h0301]=8'h33; rom[16'h0302]=8'h44;

		load_vector(5'd0, 32'h0000_0800);
		load_vector(5'd1, 32'h0080_0100);
		repeat (3) @(negedge clk);
		reset = 1'b0;
		wait (bus.work_ram.memory_lane3[14'h0101] == 8'h5a);
		repeat (20) @(posedge clk);
		if ({bus.work_ram.memory_lane3[14'h0100], bus.work_ram.memory_lane2[14'h0100],
			bus.work_ram.memory_lane1[14'h0100], bus.work_ram.memory_lane0[14'h0100]} !== 32'h1122_3344)
			$fatal(1, "TG68/main-bus odd longword mismatch got=%02x%02x%02x%02x",
				bus.work_ram.memory_lane3[14'h0100], bus.work_ram.memory_lane2[14'h0100],
				bus.work_ram.memory_lane1[14'h0100], bus.work_ram.memory_lane0[14'h0100]);
		$display("TG68_MAIN_BUS_UNALIGNED_PASS value=11223344 protection=5a rom_reads=%0d cycles=%0d", rom_reads, cycles);
		$finish;
	end
endmodule
