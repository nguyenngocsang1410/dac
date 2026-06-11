#------------------------------------------------------------------------------
# constraints.sdc -- synthesis/PnR timing constraints for dac_demdrz_top (v2)
#
# clk runs at 2x the DAC sample rate in DEMDRZ mode. The reference design
# converts at 1.6 GS/s, i.e. a 3.2 GHz encoder clock; scale CLK_PERIOD_NS to
# your target node and sample rate (the RTL is frequency-agnostic). At
# multi-GHz rates the encoder is typically clocked by the analog clock
# receiver and the sw_*/sw_*_n flops are placed adjacent to the switch
# drivers.
#------------------------------------------------------------------------------

set CLK_PERIOD_NS 1.000   ;# 1 GHz default; 0.3125 for 1.6 GS/s DEMDRZ

create_clock -name clk -period $CLK_PERIOD_NS [get_ports clk]

set_clock_uncertainty [expr {0.05 * $CLK_PERIOD_NS}] [get_clocks clk]
set_clock_transition  0.05 [get_clocks clk]

# rst is SYNCHRONOUS active-high (MAS decision D1): it is a normal timed
# data path into every flop and into the data_req/capture logic — do NOT
# false-path it. Assert >= 1 clk cycle; deassert synchronously (MAS M1/M2).
set_input_delay -clock clk [expr {0.50 * $CLK_PERIOD_NS}] [get_ports rst]

# Quasi-static configuration inputs (changed only between bursts, PRD A2).
set_false_path -from [get_ports dem_en]
set_false_path -from [get_ports drz_en]
set_false_path -from [get_ports fmt_sel]

# Synchronous functional inputs: sample data and the runtime seed write
# interface (single-cycle strobe + address + data, MAS §4.1.4).
set_input_delay -clock clk [expr {0.50 * $CLK_PERIOD_NS}] \
    [get_ports {data_in[*] seed_wr seed_addr[*] seed_wdata[*]}]

set_output_delay -clock clk [expr {0.25 * $CLK_PERIOD_NS}] [get_ports data_req]

# The 56 switch-control lines (true + complement rails, both registered in
# the same output stage) and the phase indicator drive the full-custom
# switch-driver macro; budget for the driver setup and keep the lines
# skew-matched in PnR (set_max_skew or matched routing rules in the tool).
set_output_delay -clock clk [expr {0.25 * $CLK_PERIOD_NS}] \
    [get_ports {sw_msb[*]   sw_ulsb[*]   sw_lsb[*]   sw_llsb[*] \
                sw_msb_n[*] sw_ulsb_n[*] sw_lsb_n[*] sw_llsb_n[*] phase}]

set_max_fanout 8  [current_design]
set_max_transition [expr {0.10 * $CLK_PERIOD_NS}] [current_design]
