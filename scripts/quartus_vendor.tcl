# Use the vendor library bundled with the running Quartus installation.
set_global_assignment -name VHDL_FILE [file join $::quartus(quartus_rootpath) libraries megafunctions sld_hub.vhd] -library altera_sld
