-- =============================================================================
-- bram_tdp_model  --  one of the four Block Memory Generator instances
--                     (Part0..Part3) as configured in the block design
-- TeraNova FPGA project, Kai Janssen, Nov 2026.
--
-- Settings taken from accu_to_DDR_axi_bram_ctrl_*_bram_*.xci:
--   True Dual Port, BRAM Controller mode, 8192 x 32 bit (32 KB),
--   no output registers -> read latency 1 on port B, ENB and RSTB pins used.
-- Port A (CPU side, AXI BRAM controller) is modelled as a plain word write
-- port driven by the testbench; port B is the partitioner side:
--   addrb is a BYTE address (the partitioner's word address x4 by mult_gen),
--   the memory uses addrb(14 downto 2).
-- READ_LAT = 2 models "primitive output register enabled" (what-if only).
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bram_tdp_model is
  generic (READ_LAT : integer := 1);
  port (
    clk   : in  std_logic;
    -- port A (CPU)
    wea   : in  std_logic;
    addra : in  integer range 0 to 8191;            -- 32-bit word index
    dina  : in  std_logic_vector(31 downto 0);
    -- port B (partitioner)
    enb   : in  std_logic;
    rstb  : in  std_logic;
    addrb : in  std_logic_vector(31 downto 0);      -- byte address
    doutb : out std_logic_vector(31 downto 0));
end entity;

architecture sim of bram_tdp_model is
  type mem_t is array (0 to 8191) of std_logic_vector(31 downto 0);
  signal mem : mem_t := (others => (others => '0'));
  signal q1, q2 : std_logic_vector(31 downto 0) := (others => '0');
begin
  process(clk) begin
    if rising_edge(clk) then
      if wea = '1' then mem(addra) <= dina; end if;
      if enb = '1' then
        if rstb = '1' then q1 <= (others => '0');
        else q1 <= mem(to_integer(unsigned(addrb(14 downto 2)))); end if;
        q2 <= q1;
      end if;
    end if;
  end process;
  doutb <= q1 when READ_LAT = 1 else q2;
end architecture;
