Ladder step 2_writer_fix (branch writer-fix)

Put the VHDL that Vitis HLS generates for the writer fix in the folder hls_rtl\ next to this file:
  copy C:\PLD\hls\RAM_INTERFACE\work\hls\impl\vhdl\*.vhd  C:\PLD\sim\steps\2_writer_fix\hls_rtl\

If RAM_INTERFACE_gmem_m_axi.vhd again contains a VHDL-2019 conditional constant
(constant PREFERRED_IMPL ... when ... else ...), apply the same SIM PATCH as in sim\hls_rtl
(GHDL only accepts VHDL-2008). Then: python run_ladder.py 2_writer_fix
