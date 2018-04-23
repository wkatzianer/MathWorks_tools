set ad_hdl_dir    	[pwd]
set ad_phdl_dir   	[pwd]
set proj_dir		$ad_hdl_dir/projects/fmcomms2/zc702

source $ad_hdl_dir/projects/scripts/adi_project.tcl
source $ad_hdl_dir/projects/scripts/adi_board.tcl

adi_project_create fmcomms2_zc702 $proj_dir config_rx.tcl

adi_project_files fmcomms2_zc702 [list \
  "system_top.v" \
  "system_constr.xdc"\
  "$ad_hdl_dir/library/xilinx/common/ad_iobuf.v" \
  "$ad_hdl_dir/projects/common/zc702/zc702_system_constr.xdc" ]

adi_project_run fmcomms2_zc702
source $ad_hdl_dir/library/axi_ad9361/axi_ad9361_delay.tcl

# Copy the boot file to the root directory
file copy -force $proj_dir/boot $ad_hdl_dir/boot