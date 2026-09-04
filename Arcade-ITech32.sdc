derive_pll_clocks
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
