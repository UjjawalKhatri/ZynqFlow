# ==============================================================================
# block_c.tcl  — Run in Vivado Tcl console:
# ==============================================================================

puts ">>> Block C: StreamOps Integration"

# ------------------------------------------------------------------------------
# Step 1: Clean up any partial state from previous attempt
# ------------------------------------------------------------------------------
# Remove streamops_0 if partially added from previous failed attempt
if {[llength [get_bd_cells -quiet streamops_0]] > 0} {
    puts ">>> Cleaning up partial streamops_0 from previous attempt..."
    open_bd_design C:/dma_accelerator/project_1/project_1.srcs/sources_1/bd/zynqflow_bd/zynqflow_bd.bd
    delete_bd_objs [get_bd_cells streamops_0]
    save_bd_design
}

# ------------------------------------------------------------------------------
# Step 2: Package StreamOps as IP using ipx::package_project
# (requires temporarily setting streamops_top as the project top module)
# ------------------------------------------------------------------------------
puts ">>> Packaging StreamOps as Vivado IP..."

# Save current top
set saved_top [get_property top [get_filesets sources_1]]
puts ">>> Current top: $saved_top"

# Temporarily make streamops_top the synthesis top so ipx can analyse it
set_property top streamops_top [get_filesets sources_1]
update_compile_order -fileset sources_1

# Package — this properly infers s_axi / s_axis / m_axis interfaces from port names
ipx::package_project \
    -root_dir    C:/dma_accelerator/vivado/streamops_ip \
    -vendor      xilinx.com \
    -library     user \
    -taxonomy    /UserIP \
    -import_files \
    -set_current false \
    -force

# Restore block design wrapper as top
set_property top $saved_top [get_filesets sources_1]
update_compile_order -fileset sources_1
puts ">>> Restored top to: $saved_top"

# Register the IP repo and refresh catalog
set_property ip_repo_paths C:/dma_accelerator/vivado/streamops_ip [current_project]
update_ip_catalog -rebuild
puts ">>> IP catalog updated."

# Verify IP is visible
set found_ip [get_ipdefs -quiet xilinx.com:user:streamops_top:1.0]
if {[llength $found_ip] == 0} {
    puts "ERROR: streamops_top IP not found in catalog! Aborting."
    return
}
puts ">>> Found IP: $found_ip"

# ------------------------------------------------------------------------------
# Step 3: Insert StreamOps into block design
# ------------------------------------------------------------------------------
puts ">>> Modifying block design..."
open_bd_design C:/dma_accelerator/project_1/project_1.srcs/sources_1/bd/zynqflow_bd/zynqflow_bd.bd

# Disconnect the loopback (MM2S -> S2MM direct wire)
set loopback_net [get_bd_intf_nets -quiet -of_objects \
    [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S]]
if {[llength $loopback_net] > 0} {
    delete_bd_objs $loopback_net
    puts ">>> Loopback net removed."
} else {
    puts ">>> No loopback net found (already disconnected - OK)."
}

# Also disconnect S2MM end if it has a net
set s2mm_net [get_bd_intf_nets -quiet -of_objects \
    [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]]
if {[llength $s2mm_net] > 0} {
    delete_bd_objs $s2mm_net
    puts ">>> S2MM net also disconnected."
}

# Add StreamOps IP
create_bd_cell -type ip -vlnv xilinx.com:user:streamops_top:1.0 streamops_0
puts ">>> streamops_0 created."

# Print available interface pins to confirm names
puts ">>> StreamOps interface pins:"
foreach pin [get_bd_intf_pins streamops_0/*] {
    puts "    $pin"
}

# Connect AXI4-Stream: DMA MM2S -> StreamOps -> DMA S2MM
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] \
                    [get_bd_intf_pins streamops_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins streamops_0/m_axis] \
                    [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]
puts ">>> AXI4-Stream path connected."

# Connect AXI-Lite: GP0 interconnect -> StreamOps control
apply_bd_automation \
    -rule xilinx.com:bd_rule:axi4 \
    -config { \
        Master   {/processing_system7_0/M_AXI_GP0} \
        Slave    {/streamops_0/s_axi} \
        intc_ip  {/ps7_0_axi_periph} \
        Clk_master {/processing_system7_0/FCLK_CLK0} \
        Clk_slave  {/processing_system7_0/FCLK_CLK0} \
        Clk_xbar   {/processing_system7_0/FCLK_CLK0} \
        master_apm {0} \
    } [get_bd_intf_pins streamops_0/s_axi]
puts ">>> AXI-Lite control connected."

# Connect clock and reset
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins streamops_0/aclk]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
               [get_bd_pins streamops_0/aresetn]
puts ">>> Clock and reset connected."

# Show assigned address so we know where to write from software
puts ">>> Address map:"
foreach seg [get_bd_addr_segs -of_objects [get_bd_cells streamops_0]] {
    puts "    $seg  offset=[get_property OFFSET $seg]"
}

validate_bd_design
save_bd_design
puts ">>> Block design saved."

# ------------------------------------------------------------------------------
# Step 4: Build bitstream + export XSA
# ------------------------------------------------------------------------------
puts ">>> Building bitstream (this takes a few minutes)..."
reset_run synth_1
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set status [get_property STATUS [get_runs impl_1]]
puts ">>> impl_1 status: $status"

write_hw_platform -fixed -include_bit -force \
    C:/dma_accelerator/vivado/zynqflow_bd_wrapper.xsa

puts ""
puts "============================================================"
puts ">>> Block C DONE!"
puts ">>> XSA: C:/dma_accelerator/vivado/zynqflow_bd_wrapper.xsa"
puts "============================================================"
