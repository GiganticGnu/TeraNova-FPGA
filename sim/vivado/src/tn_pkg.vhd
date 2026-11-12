-- =============================================================================
-- tn_pkg  --  shared test data for the Vivado (XSim) ladder simulation
-- Library: tn_common.  TeraNova FPGA project, Kai Janssen, Nov 2026.
--
-- Same "hello" data set as helloworld.c and sim/run_perf.py:
--   A(i,j) = i*50 + j + 1     B(i,j) = i*50 + j + 2     (row major, k = i*50 + j)
-- The data are generated here instead of being read from a_b.hex, so the
-- simulation needs no data files (no path problems in the XSim run folder).
-- c_expected(i,j) is the exact result of C = A x B for this data set.
-- (Largest value 158 393 725, fits in a VHDL integer.)
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tn_pkg is
  constant N : integer := 50;
  function a_val(k : integer) return std_logic_vector;   -- 64-bit element k of A
  function b_val(k : integer) return std_logic_vector;   -- 64-bit element k of B
  function c_expected(k : integer) return std_logic_vector; -- 64-bit element k of C
  -- integer -> "x.yy" for a value given in hundredths (for the summary table)
  function fmt_x100(v : integer) return string;
end package;

package body tn_pkg is
  function a_val(k : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(k + 1, 64));
  end function;

  function b_val(k : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(k + 2, 64));
  end function;

  function c_expected(k : integer) return std_logic_vector is
    variable i, j, s : integer;
  begin
    i := k / N; j := k mod N; s := 0;
    for p in 0 to N-1 loop
      s := s + (i*N + p + 1) * (p*N + j + 2);
    end loop;
    return std_logic_vector(to_unsigned(s, 64));
  end function;

  function fmt_x100(v : integer) return string is
    variable f : integer := v mod 100;
  begin
    if f < 10 then
      return integer'image(v / 100) & ".0" & integer'image(f);
    else
      return integer'image(v / 100) & "." & integer'image(f);
    end if;
  end function;
end package body;
