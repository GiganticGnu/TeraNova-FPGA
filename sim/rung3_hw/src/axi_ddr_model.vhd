-- =============================================================================
-- axi_ddr_model  --  what RAM_INTERFACE's m_axi_gmem sees in the block design:
--                    SmartConnect axi_smc (S01_AXI) + the PL DDR4 (ddr4_0)
-- TeraNova FPGA project, Kai Janssen, Nov 2026.
--
-- Differences with sim/axi_mem_model.vhd (which the ladder uses):
--   * the FULL 64-bit address is decoded, like the SmartConnect does.
--     RAM_INTERFACE_0's address map has ONE segment:
--       ddr4_0  0x4_0000_0000 .. 0x4_1FFF_FFFF (512 MB)
--     A burst outside it gets BRESP = DECERR and its data is dropped
--     (the old model used awaddr(31 downto 3) mod 2500, which hides any
--     wrong base address).
--   * C is stored at its real place: word w of C <-> 0x4_0000_0000 + 8*w.
--     Writes inside the DDR4 but outside C are counted and the first is logged.
--   * AWSIZE / AWBURST / WSTRB / AWLEN-vs-WLAST are checked.
--   * backdoor: 'fill' writes FILL_VAL into all of C (poison before a run),
--     rd_addr/rd_data reads C (the CPU read-back).
-- Write response latency B_LATENCY cycles after WLAST (DDR4 + SmartConnect).
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_ddr_model is
  generic (
    B_LATENCY : integer := 40;
    SEG_BASE  : unsigned(63 downto 0) := x"0000000400000000";
    SEG_BYTES : unsigned(63 downto 0) := x"0000000020000000";   -- 512 MB
    C_WORDS   : integer := 2500);
  port (
    clk, rst : in std_logic;
    awvalid : in std_logic; awready : out std_logic;
    awaddr  : in std_logic_vector(63 downto 0);
    awlen   : in std_logic_vector(7 downto 0);
    awsize  : in std_logic_vector(2 downto 0);
    awburst : in std_logic_vector(1 downto 0);
    wvalid  : in std_logic; wready : out std_logic;
    wdata   : in std_logic_vector(63 downto 0);
    wstrb   : in std_logic_vector(7 downto 0);
    wlast   : in std_logic;
    bvalid  : out std_logic; bready : in std_logic;
    bresp   : out std_logic_vector(1 downto 0);
    -- backdoor
    fill     : in std_logic;
    fill_val : in std_logic_vector(63 downto 0);
    rd_addr  : in integer range 0 to 4095;
    rd_data  : out std_logic_vector(63 downto 0);
    -- statistics (live)
    n_bursts, n_beats, n_decerr, n_outside_c, n_proto_err : out integer;
    first_bad_addr : out std_logic_vector(63 downto 0));
end entity;

architecture sim of axi_ddr_model is
  type int_arr is array (0 to 31) of integer;
  type sl_arr  is array (0 to 31) of std_logic;
  signal awready_i, wready_i : std_logic := '0';
begin
  awready <= awready_i;
  wready  <= wready_i;

  process(clk)
    type mem_t is array (0 to 4095) of std_logic_vector(63 downto 0);
    variable mem : mem_t := (others => (others => '0'));
    variable aq_word, aq_len : int_arr;        -- word index into C (or -1)
    variable aq_err, aq_out : sl_arr;          -- DECERR / outside C
    variable aq_n : integer := 0;
    variable bq_due : int_arr; variable bq_err : sl_arr;
    variable bq_n : integer := 0;
    variable beat, cyc : integer := 0;
    variable bv : std_logic := '0';
    variable bursts, beats, decerr, outside, perr : integer := 0;
    variable first_bad : std_logic_vector(63 downto 0) := (others => '0');
    variable a : unsigned(63 downto 0);
    variable w : std_logic_vector(63 downto 0);
    variable idx : integer;
  begin
    if rising_edge(clk) then
      cyc := cyc + 1;
      if rst = '1' then
        aq_n := 0; bq_n := 0; beat := 0; bv := '0';
      else
        -- B handshake of the response shown last cycle
        if bv = '1' and bready = '1' then
          for q in 0 to 30 loop bq_due(q) := bq_due(q+1); bq_err(q) := bq_err(q+1); end loop;
          bq_n := bq_n - 1;
        end if;
        -- AW
        if awvalid = '1' and awready_i = '1' then
          a := unsigned(awaddr);
          bursts := bursts + 1;
          aq_len(aq_n) := to_integer(unsigned(awlen)) + 1;
          aq_err(aq_n) := '0'; aq_out(aq_n) := '0'; aq_word(aq_n) := -1;
          if awsize /= "011" or awburst /= "01" then
            perr := perr + 1;
            report "AXI: AWSIZE=" & to_string(awsize) & " AWBURST=" & to_string(awburst) &
                   " (expected 011 = 8 bytes, 01 = INCR)" severity warning;
          end if;
          if a < SEG_BASE or a >= SEG_BASE + SEG_BYTES then
            aq_err(aq_n) := '1'; decerr := decerr + 1;
            if decerr = 1 then
              first_bad := awaddr;
              report "AXI: write burst to 0x" & to_hstring(awaddr) &
                     " is OUTSIDE the DDR4 segment -> DECERR, data dropped" severity warning;
            end if;
          elsif a - SEG_BASE >= to_unsigned(8*C_WORDS, 64) or a(2 downto 0) /= "000" then
            aq_out(aq_n) := '1'; outside := outside + 1;
            if outside = 1 and decerr = 0 then
              first_bad := awaddr;
              report "AXI: write burst to 0x" & to_hstring(awaddr) &
                     " is in the DDR4 but NOT in C (0x400000000..+20000)" severity warning;
            end if;
          else
            aq_word(aq_n) := to_integer((a - SEG_BASE) srl 3);
          end if;
          aq_n := aq_n + 1;
        end if;
        -- W
        if wvalid = '1' and wready_i = '1' and aq_n > 0 then
          beats := beats + 1;
          if wstrb /= x"FF" then
            perr := perr + 1;
            report "AXI: WSTRB=" & to_hstring(wstrb) & " (expected FF)" severity warning;
          end if;
          if aq_word(0) >= 0 then
            idx := aq_word(0) + beat;
            if idx < C_WORDS then
              w := mem(idx);
              for b in 0 to 7 loop
                if wstrb(b) = '1' then w(8*b+7 downto 8*b) := wdata(8*b+7 downto 8*b); end if;
              end loop;
              mem(idx) := w;
            end if;
          end if;
          beat := beat + 1;
          if wlast = '1' or beat = aq_len(0) then
            if (wlast = '1') /= (beat = aq_len(0)) then
              perr := perr + 1;
              report "AXI: WLAST does not match AWLEN" severity warning;
            end if;
            bq_due(bq_n) := cyc + B_LATENCY; bq_err(bq_n) := aq_err(0); bq_n := bq_n + 1;
            for q in 0 to 30 loop
              aq_word(q) := aq_word(q+1); aq_len(q) := aq_len(q+1);
              aq_err(q) := aq_err(q+1); aq_out(q) := aq_out(q+1);
            end loop;
            aq_n := aq_n - 1; beat := 0;
          end if;
        end if;
        if bq_n > 0 and cyc >= bq_due(0) then bv := '1'; else bv := '0'; end if;
      end if;
      bvalid <= bv;
      if bq_n > 0 and bq_err(0) = '1' then bresp <= "11"; else bresp <= "00"; end if;
      if rst = '0' and aq_n < 16 then awready_i <= '1'; else awready_i <= '0'; end if;
      if rst = '1' or aq_n = 0 then wready_i <= '0'; else wready_i <= '1'; end if;
      if fill = '1' then
        for k in 0 to 4095 loop mem(k) := fill_val; end loop;
      end if;
      rd_data <= mem(rd_addr);
      n_bursts <= bursts; n_beats <= beats; n_decerr <= decerr;
      n_outside_c <= outside; n_proto_err <= perr; first_bad_addr <= first_bad;
    end if;
  end process;
end architecture;
