set(psu_ddr_1_memory_1 "0x800000000;0x80000000")
set(psu_ddr_0_memory_0 "0x0;0x7ff00000")
set(ddr4_0_memory_0 "0x400000000;0x20000000")
set(psu_ocm_ram_0_memory_0 "0xfffc0000;0x40000")
set(axi_bram_ctrl_0_memory_0 "0x500018000;0x8000")
set(axi_bram_ctrl_1_memory_1 "0x500010000;0x8000")
set(axi_bram_ctrl_2_memory_2 "0x500008000;0x8000")
set(axi_bram_ctrl_3_memory_3 "0x500000000;0x8000")
set(DDR psu_ddr_0_memory_0)
set(CODE psu_ddr_0_memory_0)
set(DATA psu_ddr_0_memory_0)
set(TOTAL_MEM_CONTROLLERS "psu_ddr_1_memory_1;psu_ddr_0_memory_0;ddr4_0_memory_0;psu_ocm_ram_0_memory_0;axi_bram_ctrl_0_memory_0;axi_bram_ctrl_1_memory_1;axi_bram_ctrl_2_memory_2;axi_bram_ctrl_3_memory_3")
set(MEMORY_SECTION "MEMORY
{
	psu_ddr_1_memory_1 : ORIGIN = 0x800000000, LENGTH = 0x80000000
	psu_ddr_0_memory_0 : ORIGIN = 0x0, LENGTH = 0x7ff00000
	ddr4_0_memory_0 : ORIGIN = 0x400000000, LENGTH = 0x20000000
	psu_qspi_linear_0_memory_0 : ORIGIN = 0xc0000000, LENGTH = 0x20000000
	psu_ocm_ram_0_memory_0 : ORIGIN = 0xfffc0000, LENGTH = 0x40000
	axi_bram_ctrl_0_memory_0 : ORIGIN = 0x500018000, LENGTH = 0x8000
	axi_bram_ctrl_1_memory_1 : ORIGIN = 0x500010000, LENGTH = 0x8000
	axi_bram_ctrl_2_memory_2 : ORIGIN = 0x500008000, LENGTH = 0x8000
	axi_bram_ctrl_3_memory_3 : ORIGIN = 0x500000000, LENGTH = 0x8000
}")
set(STACK_SIZE 0x2000)
set(HEAP_SIZE 0x2000)
