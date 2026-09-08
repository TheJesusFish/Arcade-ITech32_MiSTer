derive_pll_clocks

# The dedicated clock-control mux selects one continuously locked carrier at a
# time. Analyze all downstream paths at both 47.727273 and 48 MHz, but never as
# a transfer between the mutually exclusive sources.
set board_carrier [get_clocks -nowarn {*pll_board*PLL_OUTPUT_COUNTER|divclk}]
set mame_carrier [get_clocks -nowarn {*mame_pll*PLL_OUTPUT_COUNTER|divclk}]
if {[get_collection_size $board_carrier] != 1 ||
	[get_collection_size $mame_carrier] != 1} {
	error "ITech32: dual-carrier clock collection is incomplete"
}
set_clock_groups -logically_exclusive -group $board_carrier -group $mame_carrier

# The transport PLL has two possible reference clocks, so derive_pll_clocks
# cannot select a unique master for it. Define both mutually-exclusive output
# modes explicitly at the PLL output. This also makes the entire common video,
# memory, and core domain receive timing analysis at both real carrier rates.
set transport_ref_pin [get_pins -nowarn \
	{emu|transport_pll|pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}]
set transport_vco_pin [get_pins -nowarn \
	{emu|transport_pll|pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]}]
set transport_vco_source_pin [get_pins -nowarn \
	{emu|transport_pll|pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}]
set transport_carrier_pin [get_pins -nowarn \
	{emu|transport_pll|pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
if {[get_collection_size $transport_ref_pin] != 1 ||
	[get_collection_size $transport_vco_pin] != 1 ||
	[get_collection_size $transport_vco_source_pin] != 1 ||
	[get_collection_size $transport_carrier_pin] != 1} {
	error "ITech32: transport-PLL pin collection is incomplete"
}
create_generated_clock -add -name itech32_transport_board_vco \
	-source $transport_ref_pin -master_clock $board_carrier \
	-multiply_by 7 $transport_vco_pin
create_generated_clock -add -name itech32_transport_mame_vco \
	-source $transport_ref_pin -master_clock $mame_carrier \
	-multiply_by 7 $transport_vco_pin
create_generated_clock -add -name itech32_transport_board \
	-source $transport_vco_source_pin \
	-master_clock [get_clocks itech32_transport_board_vco] \
	-divide_by 7 $transport_carrier_pin
create_generated_clock -add -name itech32_transport_mame \
	-source $transport_vco_source_pin \
	-master_clock [get_clocks itech32_transport_mame_vco] \
	-divide_by 7 $transport_carrier_pin
set_clock_groups -logically_exclusive \
	-group [get_clocks itech32_transport_board] \
	-group [get_clocks itech32_transport_mame]

# sys_top.sdc normally discovers the core's top-level `pll` instance and cuts
# unrelated transfers to the scaler, audio, HPS, SPI, and physical input-clock
# domains. This core deliberately names its source PLLs and presents the common
# domain through transport_pll, so reproduce that framework grouping for the two
# clocks defined above. Keep both transport modes in the same group here; their
# mutual exclusion is declared separately above.
set transport_domain [get_clocks -nowarn \
	{itech32_transport_board itech32_transport_mame}]
set hdmi_domain [get_clocks -nowarn {*pll_hdmi*output_counter*divclk}]
set audio_domain [get_clocks -nowarn {*pll_audio*PLL_OUTPUT_COUNTER|divclk}]
set hps_domain [get_clocks -nowarn {*h2f_user0_clk}]
set spi_domain [get_clocks -nowarn {spi_sck}]
set hdmi_serial_domain [get_clocks -nowarn {hdmi_sck}]
set fpga_clk1_domain [get_clocks -nowarn {FPGA_CLK1_50}]
set fpga_clk2_domain [get_clocks -nowarn {FPGA_CLK2_50}]
set fpga_clk3_domain [get_clocks -nowarn {FPGA_CLK3_50}]
if {[get_collection_size $transport_domain] != 2 ||
	[get_collection_size $hdmi_domain] != 1 ||
	[get_collection_size $audio_domain] != 1 ||
	[get_collection_size $hps_domain] != 1 ||
	[get_collection_size $spi_domain] != 1 ||
	[get_collection_size $hdmi_serial_domain] != 1 ||
	[get_collection_size $fpga_clk1_domain] != 1 ||
	[get_collection_size $fpga_clk2_domain] != 1 ||
	[get_collection_size $fpga_clk3_domain] != 1} {
	error "ITech32: framework clock-domain collection is incomplete"
}
set_clock_groups -exclusive \
	-group $transport_domain \
	-group $hdmi_domain \
	-group $audio_domain \
	-group $hps_domain \
	-group $spi_domain \
	-group $hdmi_serial_domain \
	-group $fpga_clk1_domain \
	-group $fpga_clk2_domain \
	-group $fpga_clk3_domain

derive_clock_uncertainty

# RESET and pll_locked are asynchronous only at these forced synchronizers.
# All released reset paths and all ordinary core logic remain fully timed.
set framework_reset_sync [get_keepers -nowarn {*|framework_reset_pipe[*]}]
set memory_reset_sync [get_keepers -nowarn {*|memory_reset_pipe[*]}]
if {[get_collection_size $framework_reset_sync] == 0 ||
	[get_collection_size $memory_reset_sync] == 0} {
	error "ITech32: reset synchronizer endpoint collection is empty"
}
set_false_path -to $framework_reset_sync
set_false_path -to $memory_reset_sync

# Only the first stage of each explicit clock-mode synchronizer receives an
# asynchronous input. Later stages remain normally timed in their destination
# clock domains.
set clock_mode_async [get_keepers -nowarn [list \
	{*|clock_mode_control|pll_ready_sync[0]} \
	{*|clock_mode_control|transport_locked_sync[0]} \
	{*|clock_mode_control|memory_quiesced_sync[0]} \
	{*|clock_mode_control|request_sync[0]} \
	{*|mame_timing_pipe[0]}]]
if {[get_collection_size $clock_mode_async] != 5} {
	error "ITech32: clock-mode synchronizer endpoint collection is incomplete"
}
set_false_path -to $clock_mode_async

# At 47.727273 MHz the 8 MHz fractional enable has 5/6-cycle spacing.
# mc6809 E and Q are two accepted enables apart; the measured minimum is 11
# fabric clocks. Restrict the exception to mc6809 architectural state.
set mc6809_regs [get_keepers -nowarn {*|mc6809i:cpu|*}]
if {[get_collection_size $mc6809_regs] == 0} {
	error "ITech32: mc6809 multicycle collection is empty"
}
set_multicycle_path -setup -end 11 -from $mc6809_regs -to $mc6809_regs
set_multicycle_path -hold -end 10 -from $mc6809_regs -to $mc6809_regs

# Scanout line-buffer data/select state changes only on exact /6 CE_PIXEL.
# Preserve the existing palette address pipeline with a conservative 2/1 pair.
set palette_sources [get_keepers -nowarn [list \
	{*|itech32_scanout:scanout|itech32_line_buffer:line_buffer*|altsyncram:memory_rtl_0|*} \
	{*|itech32_scanout:scanout|read_lane_q[*]} \
	{*|itech32_scanout:scanout|read_lane2_q[*]} \
	{*|itech32_scanout:scanout|display_buffer_select} \
	{*|itech32_scanout:scanout|display_buffer_valid}]]
set palette_targets [get_keepers -nowarn \
	{*|itech32_main_bus:main_bus|itech32_bus_byte_ram_dp:palette_lane*|altsyncram:memory_rtl_0|*}]
if {[get_collection_size $palette_sources] == 0 ||
	[get_collection_size $palette_targets] == 0} {
	error "ITech32: palette multicycle endpoint collection is empty"
}
set_multicycle_path -setup -end 2 -from $palette_sources -to $palette_targets
set_multicycle_path -hold -end 1 -from $palette_sources -to $palette_targets
