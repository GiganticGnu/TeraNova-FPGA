-- =============================================================================
-- tb_ladder  --  the whole TeraNova improvement ladder in ONE Vivado simulation
-- TeraNova FPGA project, Kai Janssen, Nov 2026.
--
-- Five copies of the PL data path, one per rung, run side by side on the same
-- 100 MHz clock and receive the same start pulse at the same moment:
--   r0  rung 0  baseline (restored design)            library rung0
--   r1  rung 1  partitioner v5b, pipelined fetch       library rung1
--   r2  rung 2  writer fix, overlapped write responses library rung2
--   r3  rung 3  partitioner v6, on-chip copy + reuse   library rung3
--   r4  rung 4  burst data path (PL reads A/B itself)  library rung4
-- Each rung library holds that rung's own RTL (see create_ladder_project.tcl),
-- so the five partitioners and the two RAM_INTERFACE versions can all have
-- the same entity names.
--
-- In the wave window the 'busy' signal of every rung is high exactly as long
-- as that rung needs for one 50x50 multiplication, so the bars show the
-- improvements directly. At the end the Tcl console shows a summary table.
--
-- Generic LAT = AXI memory latency in cycles (20 = nominal, 100 = stress).
-- With LAT = 100 the effect of rung 2 (writer fix) becomes visible.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
library tn_common;
use tn_common.tn_pkg.all;
library rung0, rung1, rung2, rung3, rung4;

entity tb_ladder is
  generic (LAT : integer := 20);
end entity;

architecture sim of tb_ladder is
  constant NR : integer := 5;
  type sl_arr  is array (0 to NR-1) of std_logic;
  type int_arr is array (0 to NR-1) of integer;
  type str_arr is array (0 to NR-1) of string(1 to 34);
  constant NAMES : str_arr := (
    "rung 0  baseline                  ",
    "rung 1  partitioner v5b           ",
    "rung 2  writer fix                ",
    "rung 3  partitioner v6 (reuse)    ",
    "rung 4  burst data path           ");

  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal start    : std_logic := '0';
  signal finished : boolean := false;

  signal busy, done, checked : sl_arr;
  signal cycles, mult_busy, blocks, t_done, errors : int_arr;
  signal all_checked : std_logic := '0';

  function pass_str(e : integer) return string is
  begin
    if e = 0 then return "PASS (2500/2500)"; else return "FAIL (" & integer'image(e) & " wrong)"; end if;
  end function;
  function prev(r : integer) return integer is
  begin
    if r = 0 then return 0; else return r - 1; end if;
  end function;
begin
  clk <= not clk after 5 ns when not finished;    -- 100 MHz

  r0 : entity rung0.rung_core generic map (B_LATENCY => LAT)
    port map (clk => clk, rst => rst, start => start, busy => busy(0), done_o => done(0),
              pl_cycles => cycles(0), mult_busy => mult_busy(0), blocks => blocks(0),
              t_done_ns => t_done(0), checked => checked(0), errors => errors(0));
  r1 : entity rung1.rung_core generic map (B_LATENCY => LAT)
    port map (clk => clk, rst => rst, start => start, busy => busy(1), done_o => done(1),
              pl_cycles => cycles(1), mult_busy => mult_busy(1), blocks => blocks(1),
              t_done_ns => t_done(1), checked => checked(1), errors => errors(1));
  r2 : entity rung2.rung_core generic map (B_LATENCY => LAT)
    port map (clk => clk, rst => rst, start => start, busy => busy(2), done_o => done(2),
              pl_cycles => cycles(2), mult_busy => mult_busy(2), blocks => blocks(2),
              t_done_ns => t_done(2), checked => checked(2), errors => errors(2));
  r3 : entity rung3.rung_core generic map (B_LATENCY => LAT)
    port map (clk => clk, rst => rst, start => start, busy => busy(3), done_o => done(3),
              pl_cycles => cycles(3), mult_busy => mult_busy(3), blocks => blocks(3),
              t_done_ns => t_done(3), checked => checked(3), errors => errors(3));
  r4 : entity rung4.rung_core generic map (B_LATENCY => LAT)
    port map (clk => clk, rst => rst, start => start, busy => busy(4), done_o => done(4),
              pl_cycles => cycles(4), mult_busy => mult_busy(4), blocks => blocks(4),
              t_done_ns => t_done(4), checked => checked(4), errors => errors(4));

  -- reset and start: same timing as tb_chain_rtl
  process
    variable all_ok : boolean;
    function pad(s : string; w : integer) return string is
      variable r : string(1 to w) := (others => ' ');
    begin
      if s'length >= w then return s; end if;
      r(w - s'length + 1 to w) := s;               -- right-aligned
      return r;
    end function;
    variable l : line;
    procedure say(s : string) is              -- one clean line in the Tcl console / log
    begin
      write(l, s); writeline(output, l);
    end procedure;
  begin
    rst <= '1';
    wait for 100 ns;
    wait until rising_edge(clk);
    rst <= '0';
    wait for 50 ns;
    wait until rising_edge(clk);
    start <= '1';                                  -- one start pulse for all five rungs
    wait until rising_edge(clk);
    start <= '0';

    -- wait until every rung has finished and checked its result
    loop
      wait until rising_edge(clk);
      exit when checked = (sl_arr'(others => '1'));
    end loop;
    all_checked <= '1';

    say("");
    say("==================== TeraNova improvement ladder (Vivado XSim) ====================");
    say("AXI memory latency L = " & integer'image(LAT) & " cycles, clock 100 MHz (10 ns per cycle)");
    say("rung                                 PL cycles   PL time (us)   vs previous   vs baseline   multiplier busy   result");
    all_ok := true;
    for r in 0 to NR-1 loop
      if errors(r) /= 0 then all_ok := false; end if;
      say(NAMES(r)
        & pad(integer'image(cycles(r)), 12)
        & pad(fmt_x100(cycles(r)), 15)
        & pad(fmt_x100((cycles(prev(r)) * 100) / cycles(r)) & "x", 14)
        & pad(fmt_x100((cycles(0) * 100) / cycles(r)) & "x", 14)
        & pad(fmt_x100((mult_busy(r) * 10000) / cycles(r)) & " %", 18)
        & "   " & pass_str(errors(r)));
    end loop;
    if all_ok then
      say("ALL RUNGS PASS: every rung computed all 2500 result words of C = A x B correctly");
    else
      report "SOME RUNGS FAILED, see the errors above" severity error;
    end if;
    say("===================================================================================");
    say("");
    wait for 100 ns;
    finished <= true;                              -- stop the clock: the simulation ends
    wait;
  end process;
end architecture;
