# -----------------------------------------------------------------------------
# 5_partitioner_v6.tcl
# Ladder step 3_partitioner_v6: puts partitioner v6 (on-chip copy of A and B,
# 25 banks, 10x reuse; simulated 30 Oct 2026) into the design as core revision 6.
# Run ONLY on the git branch "partitioner-v6", in the Vivado 2025.1.1 Tcl console
# with S7_integration.xpr open:
#   source C:/PLD/scripts/5_partitioner_v6.tcl
# -----------------------------------------------------------------------------
set pv_variant  v6
set pv_revision 6
set pv_branch   partitioner-v6
source C:/PLD/scripts/install_partitioner.tcl
