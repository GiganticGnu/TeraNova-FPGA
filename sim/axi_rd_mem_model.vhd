-- AXI4 read-only slave memory model for simulation (PS DDR seen through an HP port).
--  * 128-bit data, INCR bursts of up to 256 beats, up to MAX_OUT outstanding reads
--  * the first beat of a burst comes R_LATENCY cycles after its address was accepted,
--    then one beat per cycle while RREADY is high; bursts are answered in order (one ID)
--  * checks: ARSIZE = 16 bytes, ARBURST = INCR, address 16-byte aligned,
--    no burst crosses a 4 KB boundary
--  * contents: a_b.hex (A then B, 2500 x 64-bit each, row major), placed at the
--    byte addresses A_BASE and B_BASE; beat = two consecutive 64-bit elements,
--    the lower address in bits 63..0 (little endian)
--  * counts read bursts, read beats and the maximum number of reads in flight
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity axi_rd_mem_model is
  generic (WORDS64   : integer := 8192;       -- 64 KB
           A_BASE    : integer := 16#0000#;
           B_BASE    : integer := 16#5000#;
           R_LATENCY : integer := 20;
           MAX_OUT   : integer := 8);
  port (
    clk, rst : in std_logic;
    arvalid : in std_logic; arready : out std_logic;
    araddr  : in std_logic_vector(63 downto 0);
    arlen   : in std_logic_vector(7 downto 0);
    arsize  : in std_logic_vector(2 downto 0);
    arburst : in std_logic_vector(1 downto 0);
    rvalid  : out std_logic; rready : in std_logic;
    rdata   : out std_logic_vector(127 downto 0);
    rlast   : out std_logic;
    rresp   : out std_logic_vector(1 downto 0);
    n_rbursts, n_rbeats, max_rout : out integer);
end entity;

architecture sim of axi_rd_mem_model is
  type mem_t is array (0 to WORDS64-1) of std_logic_vector(63 downto 0);
  type int_arr is array (0 to 31) of integer;
  signal arready_i, rvalid_i, rlast_i : std_logic := '0';
  signal rdata_i : std_logic_vector(127 downto 0) := (others => '0');
begin
  arready <= arready_i; rvalid <= rvalid_i; rlast <= rlast_i; rdata <= rdata_i;
  rresp <= "00";

  process(clk)
    variable mem : mem_t := (others => (others => '0'));
    variable loaded : boolean := false;
    file f : text;
    variable l : line; variable v : std_logic_vector(63 downto 0);
    variable q_addr, q_len, q_due : int_arr;   -- outstanding bursts (word64 address, beats, due cycle)
    variable q_n : integer := 0;
    variable beat : integer := 0;              -- next beat of the head burst
    variable cyc : integer := 0;
    variable bursts, beats, maxo : integer := 0;
    variable a, ln : integer;
  begin
    if rising_edge(clk) then
      if not loaded then
        file_open(f, "a_b.hex", read_mode);
        for k in 0 to 2499 loop readline(f, l); hread(l, v); mem(A_BASE/8 + k) := v; end loop;
        for k in 0 to 2499 loop readline(f, l); hread(l, v); mem(B_BASE/8 + k) := v; end loop;
        file_close(f);
        loaded := true;
      end if;
      cyc := cyc + 1;
      if rst = '1' then
        q_n := 0; beat := 0;
      else
        -- R handshake of the beat shown in the previous cycle
        if rvalid_i = '1' and rready = '1' then
          beats := beats + 1;
          if beat = q_len(0) - 1 then
            for k in 0 to 30 loop
              q_addr(k) := q_addr(k+1); q_len(k) := q_len(k+1); q_due(k) := q_due(k+1);
            end loop;
            q_n := q_n - 1; beat := 0;
          else
            beat := beat + 1;
          end if;
        end if;
        -- AR handshake
        if arvalid = '1' and arready_i = '1' then
          a  := to_integer(unsigned(araddr(31 downto 0)));
          ln := to_integer(unsigned(arlen)) + 1;
          assert arsize = "100" report "ARSIZE must be 16 bytes" severity error;
          assert arburst = "01" report "ARBURST must be INCR" severity error;
          assert a mod 16 = 0 report "read address not 16-byte aligned" severity error;
          assert (a mod 4096) + ln * 16 <= 4096 report "read burst crosses a 4 KB boundary" severity error;
          q_addr(q_n) := a / 8; q_len(q_n) := ln; q_due(q_n) := cyc + R_LATENCY;
          q_n := q_n + 1; bursts := bursts + 1;
          if q_n > maxo then maxo := q_n; end if;
        end if;
      end if;
      -- drive the next beat
      if rst = '0' and q_n > 0 and cyc >= q_due(0) then
        rvalid_i <= '1';
        rdata_i  <= mem((q_addr(0) + 2*beat + 1) mod WORDS64) & mem((q_addr(0) + 2*beat) mod WORDS64);
        if beat = q_len(0) - 1 then rlast_i <= '1'; else rlast_i <= '0'; end if;
      else
        rvalid_i <= '0'; rlast_i <= '0';
      end if;
      if rst = '0' and q_n < MAX_OUT then arready_i <= '1'; else arready_i <= '0'; end if;
      n_rbursts <= bursts; n_rbeats <= beats; max_rout <= maxo;
    end if;
  end process;
end architecture;
