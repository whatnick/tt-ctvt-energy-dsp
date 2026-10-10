source $::env(SCRIPTS_DIR)/base.sdc

# The ADC and host interfaces are asynchronous to the Tiny Tapeout core clock.
# Their first-stage synchronizers and externally-timed SPI paths are verified
# functionally rather than as core-clock synchronous paths.
set_false_path -from [get_ports {rst_n ena ui_in* uio_in*}]
