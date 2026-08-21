# Extract reports from an already-routed checkpoint (no rebuild needed).
#   vivado -mode batch -nolog -nojournal -source reports_from_dcp.tcl -tclargs <dcp> <outdir>
set dcp [lindex $argv 0]; set out [lindex $argv 1]
file mkdir $out
open_checkpoint $dcp
report_utilization -file $out/util_impl.rpt
report_utilization -hierarchical -hierarchical_depth 3 -file $out/util_hier_impl.rpt
report_timing_summary -delay_type max -max_paths 10 -file $out/timing_impl.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "RESULT_FROM_DCP: WNS=$wns ns"
puts [exec grep -m1 -A6 "CLB LUTs" $out/util_impl.rpt]
exit 0
