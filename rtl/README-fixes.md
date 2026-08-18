# What was changed vs. the raw coralnpu emit

Both file sets are the unmodified output of coralnpu's own Bazel targets
(`//hdl/chisel/src/coralnpu/prod:{core_mini_axi,rvv_core_mini_axi}_prod_cc_library_emit_verilog`
at commit 44141a10), i.e. the contents of `CoreMiniAxi.zip` / `RvvCoreMiniAxi.zip`,
with exactly one mechanical fix applied so they synthesize outside Bazel:

* fpnew (CVFPU) sources use `` `FF*`` register macros from `registers.svh` but the
  packaged files carry no `` `include``. Each fpnew file that uses those macros got
  `` `include "registers.svh" `` inserted as its first line, and the build passes
  the RTL directory as an include dir.

The RVV set additionally needs the defines `VLEN_128 ZVE32F_ON USE_GENERIC`
(taken from coralnpu's `tests/vcs_sim/BUILD`), which `build/build.tcl` sets.
No functional edits.
