`timescale 1ns/1ps

// Scanout plane geometry against MAME 0.288 itech32_state::screen_update on a
// reduced 16x12 raster. Each line starts at compute_safe_address(xorigin,
// yorigin + y), masking the row to the plane height and the column to 511,
// then walks linearly; reads past the last row see MAME's 0x00ff guard rows.
// With two planes, plane 0 pixels whose low byte is 0xff show plane 1 at
// (xorigin2 + xscroll2, yorigin2 + yscroll2 + y). Profiles: SFTM (one
// 1024-row plane), Time Killers (two 512-row planes) and Golden Tee (two
// 1024-row planes), with origins that cross a row end, wrap the plane, and
// reach the guard rows.
module itech32_scanout_planes_tb;
    import itech32_profile_pkg::*;
    localparam integer LINE_PIXELS = 16;
    localparam integer ROW_WORDS = (LINE_PIXELS + 6) / 4;
    localparam logic [9:0] HTOTAL = 10'd32, HBLANK_END = 10'd8;
    localparam logic [9:0] VTOTAL = 10'd20, VBLANK_START = 10'd16, VBLANK_END = 10'd4;
    localparam integer VISIBLE_LINES = 12;

    logic clk = 1'b0, reset = 1'b1;
    logic [7:0] selector = SELECT_SFTM;
    logic ce_pixel = 1'b0;
    logic [1:0] ce_div = 2'd0;
    logic [9:0] hpos = 10'd0, vpos = 10'd0;
    logic hblank, vblank;
    logic [8:0] xorigin = 9'd0, xorigin2 = 9'd0, xscroll2 = 9'd0;
    logic [9:0] yorigin = 10'd0, yorigin2 = 10'd0, yscroll2 = 10'd0;
    logic fb_req, fb_accept, fb_data_valid, fb_last;
    logic [19:0] fb_addr;
    logic [63:0] fb_rdata;
    logic [14:0] palette_addr;
    logic [15:0] pixel_data;
    logic pixel_valid, underflow;
    integer checks = 0;

    always #5 clk = ~clk;

    assign hblank = hpos < HBLANK_END || hpos >= HBLANK_END + 10'd20;
    assign vblank = vpos >= VBLANK_START || vpos < VBLANK_END;

    itech32_scanout #(.LINE_PIXELS(LINE_PIXELS)) dut (
        .clk(clk), .reset(reset), .profile(profile_for_selector(selector)),
        .ce_pixel(ce_pixel), .hpos(hpos), .vpos(vpos), .hblank(hblank), .vblank(vblank),
        .htotal(HTOTAL), .hblank_end(HBLANK_END), .vtotal(VTOTAL),
        .vblank_start(VBLANK_START), .vblank_end(VBLANK_END),
        .display_xorigin(xorigin), .display_yorigin(yorigin),
        .display_xorigin2(xorigin2), .display_yorigin2(yorigin2),
        .display_xscroll2(xscroll2), .display_yscroll2(yscroll2),
        .fb_req(fb_req), .fb_addr(fb_addr), .fb_accept(fb_accept),
        .fb_data_valid(fb_data_valid), .fb_rdata(fb_rdata), .fb_last(fb_last),
        .palette_addr(palette_addr), .pixel_data(pixel_data),
        .pixel_valid(pixel_valid), .underflow(underflow)
    );

    // Raster: one pixel every four clocks.
    always @(posedge clk) begin
        ce_div <= ce_div + 2'd1;
        ce_pixel <= ce_div == 2'd2;
        if (ce_pixel) begin
            if (hpos == HTOTAL - 10'd1) begin
                hpos <= 10'd0;
                vpos <= (vpos == VTOTAL - 10'd1) ? 10'd0 : vpos + 10'd1;
            end else
                hpos <= hpos + 10'd1;
        end
    end

    // Logical framebuffer word for plane/row/column. About a third of plane 0
    // is transparent (low byte 0xff); no other word has that low byte.
    function automatic logic [15:0] vram_word(input integer plane, input integer row,
        input integer column);
        integer hash;
        begin
            hash = (row * 37 + column * 11 + plane * 101) & 16'h7fff;
            if (plane == 0 && ((row + column) % 3) == 0)
                vram_word = {hash[15:8], 8'hff};
            else if (hash[7:0] == 8'hff)
                vram_word = {hash[15:8], 8'hfe};
            else
                vram_word = hash[15:0];
        end
    endfunction

    // MAME's linear walk from compute_safe_address, with guard rows after the
    // plane's last row.
    function automatic logic [15:0] mame_pixel(input integer plane, input integer rows,
        input integer x_origin, input integer y_line, input integer x);
        integer linear;
        begin
            linear = (y_line % rows) * 512 + (x_origin % 512) + x;
            if (linear >= rows * 512)
                mame_pixel = 16'h00ff;
            else
                mame_pixel = vram_word(plane, linear / 512, linear % 512);
        end
    endfunction

    function automatic logic [15:0] expected_pixel(input integer y, input integer x);
        board_profile_t profile;
        integer rows;
        logic [15:0] pixel;
        begin
            profile = profile_for_selector(selector);
            rows = profile.vram_512_rows ? 512 : 1024;
            pixel = mame_pixel(0, rows, int'(xorigin), int'(yorigin) + y, x);
            if (profile.vram_two_planes && pixel[7:0] == 8'hff)
                pixel = mame_pixel(1, rows, int'(xorigin2) + int'(xscroll2),
                    int'(yorigin2) + int'(yscroll2) + y, x);
            expected_pixel = pixel;
        end
    endfunction

    // DDR model: accept at once, then ROW_WORDS consecutive qwords after a
    // short latency. Physical words are {plane, row, column}, linear, with
    // each 16-bit word's bytes swapped as on MiSTer DDR.
    integer beat = -1, latency = 0;
    logic [19:0] burst_addr;
    assign fb_accept = fb_req && beat < 0 && latency == 0;
    always @(posedge clk) begin
        fb_data_valid <= 1'b0;
        fb_last <= 1'b0;
        if (fb_accept) begin
            burst_addr <= fb_addr;
            latency <= 3;
        end else if (latency > 1)
            latency <= latency - 1;
        else if (latency == 1) begin
            latency <= 0;
            beat <= 0;
        end
        if (beat >= 0) begin
            for (int lane = 0; lane < 4; lane++) begin
                logic [19:0] word_addr;
                logic [15:0] word;
                word_addr = burst_addr + 20'(beat * 4 + lane);
                word = vram_word(int'(word_addr[19]), int'(word_addr[18:9]), int'(word_addr[8:0]));
                fb_rdata[lane * 16 +: 16] <= {word[7:0], word[15:8]};
            end
            fb_data_valid <= 1'b1;
            fb_last <= beat == ROW_WORDS - 1;
            beat <= (beat == ROW_WORDS - 1) ? -1 : beat + 1;
        end
    end

    // Compare every visible pixel of the frames after the first.
    task automatic check_board(input string label, input logic [7:0] value);
        integer mismatches, frames;
        begin
            @(negedge clk);
            reset = 1'b1;
            selector = value;
            repeat (8) @(negedge clk);
            reset = 1'b0;
            // Wait out the first frame, then check two complete frames.
            wait (vpos == VBLANK_START); wait (vpos == 0);
            mismatches = 0;
            for (frames = 0; frames < 2; frames++) begin
                wait (vpos == VBLANK_END && hpos == 0);
                for (int y = 0; y < VISIBLE_LINES; y++) begin
                    for (int x = 0; x < LINE_PIXELS; x++) begin
                        wait (vpos == VBLANK_END + 10'(y) && hpos == HBLANK_END + 10'(x));
                        @(posedge clk); @(posedge clk); #1;
                        if (!pixel_valid || pixel_data !== expected_pixel(y, x)) begin
                            if (mismatches < 8)
                                $display("SCANOUT_%s y=%0d x=%0d valid=%0b got=%04x expected=%04x",
                                    label, y, x, pixel_valid, pixel_data, expected_pixel(y, x));
                            mismatches++;
                        end
                        checks++;
                    end
                end
                wait (vpos == VBLANK_START);
            end
            if (mismatches != 0) $fatal(1, "SCANOUT_%s mismatches=%0d", label, mismatches);
        end
    endtask

    initial begin
        #20000000;
        $fatal(1, "SCANOUT_GLOBAL_TIMEOUT");
    end

    initial begin
        // SFTM: one plane; a 1024-row wrap and a row-end crossing. Transparent
        // words are shown as stored.
        xorigin = 9'd501; yorigin = 10'd1018;
        xorigin2 = 9'd7; yorigin2 = 10'd200; xscroll2 = 9'd0; yscroll2 = 10'd0;
        check_board("SFTM", SELECT_SFTM);
        // Time Killers: 512-row planes, both wrapping; plane 1 reaches row 511's
        // guard words.
        xorigin = 9'd100; yorigin = 10'd505;
        xorigin2 = 9'd500; yorigin2 = 10'd508; xscroll2 = 9'd0; yscroll2 = 10'd3;
        check_board("TIMEKILL", SELECT_TIMEKILL);
        // Golden Tee: 1024-row planes. Plane 0 crosses row ends, reaches row
        // 1023's guard words, and wraps to row 0; plane 1 sits above row 511
        // and its origin plus scroll wraps the column mask.
        xorigin = 9'd501; yorigin = 10'd1015;
        xorigin2 = 9'd300; xscroll2 = 9'd250; yorigin2 = 10'd600; yscroll2 = 10'd0;
        check_board("GOLDEN_TEE", SELECT_GT_AAMA);
        // The Golden Tee 3D boards share the plane geometry; here plane 1
        // reaches the guard words and wraps.
        xorigin = 9'd3; yorigin = 10'd700;
        xorigin2 = 9'd500; xscroll2 = 9'd0; yorigin2 = 10'd1015; yscroll2 = 10'd3;
        check_board("GT3D", SELECT_GT3D_SHORT);
        $display("SCANOUT_PLANES_PASS checks=%0d boards=4", checks);
        $finish;
    end
endmodule
