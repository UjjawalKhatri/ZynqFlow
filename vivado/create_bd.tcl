# ==============================================================================
# create_bd.tcl
# ==============================================================================
#
#
# This script creates a block design called "zynqflow_bd" with:
#   - Zynq PS (ZedBoard preset, DDR3, M_AXI_GP0, S_AXI_HP0, IRQ_F2P)
#   - AXI DMA (simple mode, no SG, 64-bit stream, 64-bit memory-mapped)
#   - Direct MM2S -> S2MM loopback (no StreamOps yet)
#   - Interrupt wiring via xlconcat
#   - Proper clock and reset distribution
#
# After running this script:
#   1. Generate HDL wrapper
#   2. Run Synthesis
#   3. Run Implementation
#   4. Generate Bitstream
#   5. Export Hardware (XSA)
#
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Create Block Design
# ------------------------------------------------------------------------------
puts ">>> Creating block design: zynqflow_bd"
create_bd_design "zynqflow_bd"

# ------------------------------------------------------------------------------
# 2. Add Zynq Processing System
# ------------------------------------------------------------------------------
puts ">>> Adding Zynq PS"
set ps [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0 ]

# Apply ZedBoard preset (configures DDR3, MIO, clocks, etc.)
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config { \
        make_external {FIXED_IO, DDR} \
        Master_Disable {0} \
    } [get_bd_cells processing_system7_0]

# Configure PS: enable HP0, GP0, IRQ_F2P, set FCLK_CLK0 to 100 MHz
set_property -dict [list \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
] $ps

# ------------------------------------------------------------------------------
# 3. Add Processor System Reset
# ------------------------------------------------------------------------------
puts ">>> Adding Processor System Reset"
set rst [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0 ]

# Connect reset block
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
               [get_bd_pins proc_sys_reset_0/ext_reset_in]

# ------------------------------------------------------------------------------
# 4. Add AXI DMA (Simple Mode)
# ------------------------------------------------------------------------------
puts ">>> Adding AXI DMA"
set dma [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0 ]

# Configure DMA:
#   - Scatter Gather: DISABLED (simple/direct register mode)
#   - MM2S: Enabled, 64-bit memory-mapped data width, 64-bit stream
#   - S2MM: Enabled, 64-bit memory-mapped data width, 64-bit stream
#   - Max burst: 16 beats
#   - No DRE (aligned transfers only)
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_s2mm_burst_size {16} \
    CONFIG.c_include_mm2s_dre {0} \
    CONFIG.c_include_s2mm_dre {0} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {64} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_s_axis_s2mm_tdata_width {64} \
] $dma

# ------------------------------------------------------------------------------
# 5. Connect AXI DMA control path (S_AXI_LITE -> GP0)
# ------------------------------------------------------------------------------
puts ">>> Connecting DMA control path via GP0"

# Use automation to connect DMA S_AXI_LITE to PS M_AXI_GP0
# This creates the AXI Interconnect automatically
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config { \
        Clk_master {/processing_system7_0/FCLK_CLK0 (100 MHz)} \
        Clk_slave {/processing_system7_0/FCLK_CLK0 (100 MHz)} \
        Clk_xbar {/processing_system7_0/FCLK_CLK0 (100 MHz)} \
        Master {/processing_system7_0/M_AXI_GP0} \
        Slave {/axi_dma_0/S_AXI_LITE} \
        intc_ip {New AXI Interconnect} \
        master_apm {0} \
    } [get_bd_intf_pins axi_dma_0/S_AXI_LITE]

# ------------------------------------------------------------------------------
# 6. Connect AXI DMA data path (MM2S + S2MM memory ports -> HP0)
# ------------------------------------------------------------------------------
puts ">>> Connecting DMA data path via HP0"

# Connect MM2S memory-mapped port to HP0
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config { \
        Clk_master {/processing_system7_0/FCLK_CLK0 (100 MHz)} \
        Clk_slave {/processing_system7_0/FCLK_CLK0 (100 MHz)} \
        Clk_xbar {/processing_system7_0/FCLK_CLK0 (100 MHz)} \
        Master {/axi_dma_0/M_AXI_MM2S} \
        Slave {/processing_system7_0/S_AXI_HP0} \
        intc_ip {New AXI Interconnect} \
        master_apm {0} \
    } [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

# Connect S2MM memory-mapped port to same HP0 interconnect
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config { \
        Clk_master {/processing_system7_0/FCLK_CLK0 (100 MHz)} \
        Clk_slave {/processing_system7_0/FCLK_CLK0 (100 MHz)} \
        Clk_xbar {/processing_system7_0/FCLK_CLK0 (100 MHz)} \
        Master {/axi_dma_0/M_AXI_S2MM} \
        Slave {/processing_system7_0/S_AXI_HP0} \
        intc_ip {/axi_mem_intercon} \
        master_apm {0} \
    } [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

# ------------------------------------------------------------------------------
# 7. Direct loopback: MM2S stream -> S2MM stream
# ------------------------------------------------------------------------------
puts ">>> Connecting direct stream loopback (MM2S -> S2MM)"
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] \
                    [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# ------------------------------------------------------------------------------
# 8. Interrupt wiring
# ------------------------------------------------------------------------------
puts ">>> Wiring interrupts"

# Add concat block for 2 interrupts
set concat [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0 ]
set_property CONFIG.NUM_PORTS {2} $concat

# Connect DMA interrupts to concat
connect_bd_net [get_bd_pins axi_dma_0/mm2s_introut] \
               [get_bd_pins xlconcat_0/In0]
connect_bd_net [get_bd_pins axi_dma_0/s2mm_introut] \
               [get_bd_pins xlconcat_0/In1]

# Connect concat output to PS IRQ_F2P
connect_bd_net [get_bd_pins xlconcat_0/dout] \
               [get_bd_pins processing_system7_0/IRQ_F2P]

# ------------------------------------------------------------------------------
# 9. Validate design
# ------------------------------------------------------------------------------
puts ">>> Validating block design..."
validate_bd_design

# Save
save_bd_design

puts ">>> Block design 'zynqflow_bd' created successfully!"
puts ""
puts "Next steps:"
puts "  1. Right-click zynqflow_bd in Sources -> Create HDL Wrapper (Let Vivado manage)"
puts "  2. Run Synthesis"
puts "  3. Run Implementation"  
puts "  4. Generate Bitstream"
puts "  5. File -> Export Hardware -> Include bitstream -> Save as .xsa"
puts ""
puts "Or run these Tcl commands:"
puts "  make_wrapper -files [get_files zynqflow_bd.bd] -top"
puts "  add_files -norecurse [get_files zynqflow_bd_wrapper.v]"
puts "  update_compile_order -fileset sources_1"
puts "  launch_runs synth_1 -jobs 4"
puts "  wait_on_run synth_1"
puts "  launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "  wait_on_run impl_1"
