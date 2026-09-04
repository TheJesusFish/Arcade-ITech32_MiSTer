`timescale 1ns/1ps

module itech32_inputs_tb;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic timekill_mode = 1'b0;
	logic bloodstorm_mode = 1'b0;
	logic [11:0] joystick_0 = 12'd0;
	logic [11:0] joystick_1 = 12'd0;
	logic service_button = 1'b0;
	logic vblank = 1'b0;
	logic sound_special = 1'b0;
	logic [7:0] dip_switches = 8'd0;
	logic [31:0] input_p1, input_p2, input_p3, input_p4, input_dips, input_extra;

	itech32_inputs dut (.*);
	always #5 clk = ~clk;

	initial begin
		repeat (2) @(posedge clk);
		@(negedge clk);
		reset = 1'b0;
		@(posedge clk);
		#1;
		assert (input_p1 == 32'h00ff_0000 && input_p2 == 32'h00ff_0000)
			else $fatal(1, "inactive P1/P2 values %x/%x", input_p1, input_p2);
		assert (input_p3 == 32'h00ff_0000 && input_p4 == 32'h00ff_0000)
			else $fatal(1, "inactive P3/P4 values %x/%x", input_p3, input_p4);
		assert (input_dips == 32'h000f_0000)
			else $fatal(1, "inactive DIP value %x", input_dips);

		joystick_0 = 12'd0;
		joystick_0[0] = 1'b1;   // right
		joystick_0[3] = 1'b1;   // up
		joystick_0[4] = 1'b1;   // B1
		joystick_0[6] = 1'b1;   // B3 on P3
		joystick_0[8] = 1'b1;   // B5 on P3
		joystick_0[10] = 1'b1;  // start
		joystick_0[11] = 1'b1;  // coin
		joystick_1[5] = 1'b1;   // P2 B2
		joystick_1[7] = 1'b1;   // P2 B4 on P3
		joystick_1[9] = 1'b1;   // P2 B6 on P3
		#1;
		assert (input_p1[23:16] == 8'hff)
			else $fatal(1, "controller payload changed before registered boundary");
		@(posedge clk);
		#1;
		assert (input_p1[23:16] == 8'b0110_1000)
			else $fatal(1, "P1 mapping %b", input_p1[23:16]);
		assert (input_p2[23:16] == 8'b1111_0111)
			else $fatal(1, "P2 mapping %b", input_p2[23:16]);
		assert (input_p3[23:16] == 8'b0110_0110)
			else $fatal(1, "P3 extra-button mapping %b", input_p3[23:16]);

		service_button = 1'b1;
		vblank = 1'b1;
		sound_special = 1'b1;
		dip_switches = 8'b0000_1010;
		#1;
		assert (input_dips[23:16] == 8'b1010_0010)
			else $fatal(1, "dynamic/DIP mapping %b", input_dips[23:16]);

		timekill_mode = 1'b1;
		joystick_0 = 12'd0;
		joystick_1 = 12'd0;
		service_button = 1'b0;
		vblank = 1'b0;
		sound_special = 1'b0;
		dip_switches = 8'b0100_0000;
		@(posedge clk);
		#1;
		assert (input_p1[31:16] == 16'hffff && input_p2[31:16] == 16'hffff)
			else $fatal(1, "Time Killers inactive P1/P2 %x/%x", input_p1, input_p2);
		assert (input_p3[31:16] == 16'hffff)
			else $fatal(1, "Time Killers inactive SYSTEM %x", input_p3);
		assert (input_dips[31:16] == 16'hff47)
			else $fatal(1, "Time Killers inactive DIPS %x", input_dips);

		joystick_0[0] = 1'b1;  // right
		joystick_0[3] = 1'b1;  // up
		joystick_0[4] = 1'b1;  // button 1
		joystick_0[7] = 1'b1;  // button 4
		joystick_0[8] = 1'b1;  // button 5
		joystick_0[10] = 1'b1; // start
		joystick_0[11] = 1'b1; // coin
		@(posedge clk);
		#1;
		assert (input_p1[23:16] == 8'b0110_0110)
			else $fatal(1, "Time Killers P1 %b", input_p1[23:16]);
		assert (input_p3[23:16] == 8'b1111_1000)
			else $fatal(1, "Time Killers SYSTEM %b", input_p3[23:16]);

		$display("PASS: SFTM six-button and Time Killers five-button/DIP mappings");
		$finish;
	end

endmodule
