-- =============================================================================
-- hw_pkg  --  test data and golden model for the rung-3 hardware simulation
-- TeraNova FPGA project, Kai Janssen, Nov 2026.
--
-- Same data as the rung-3 application (helloworld.c on branch partitioner-v6):
--   A(i,j) = i*50 + j + A_OFF       B(i,j) = i*50 + j + B_OFF
-- (A_OFF = 1, B_OFF = 2.  Badr's own test used B_OFF = 7: change it below.)
-- All arithmetic is 64-bit unsigned modulo 2^64, exactly like the hardware
-- (the accumulator keeps 128 bits, RAM_INTERFACE writes the low 64).
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package hw_pkg is
  constant N     : integer := 50;
  constant BLK    : integer := 5;              -- block size
  constant NB    : integer := N / BLK;         -- 10 blocks per row / column
  constant A_OFF : integer := 1;
  constant B_OFF : integer := 2;

  subtype u64 is unsigned(63 downto 0);
  type u64_arr is array (natural range <>) of u64;

  -- value written into C before every run: anything still equal to this
  -- afterwards was NEVER written by the PL
  constant POISON : std_logic_vector(63 downto 0) := x"DEADBEEFDEADBEEF";

  function a_el(r, c : integer) return u64;
  function b_el(r, c : integer) return u64;
  function c_golden return u64_arr;           -- 2500 values, row major
  -- element e (= 5*row + col) of the 5x5 product A(ib,pb) x B(pb,jb)
  function m_el(ib, jb, pb, e : integer) return u64;

  function hex(v : std_logic_vector) return string;
  function hex(v : unsigned) return string;
  function us2(ns : integer) return string;  -- 123456 ns -> "123.46"
end package;

package body hw_pkg is
  function a_el(r, c : integer) return u64 is
  begin
    return to_unsigned(r*N + c + A_OFF, 64);
  end function;

  function b_el(r, c : integer) return u64 is
  begin
    return to_unsigned(r*N + c + B_OFF, 64);
  end function;

  function c_golden return u64_arr is
    variable res : u64_arr(0 to N*N-1);
    variable s : u64;
  begin
    for i in 0 to N-1 loop
      for j in 0 to N-1 loop
        s := (others => '0');
        for k in 0 to N-1 loop
          s := s + resize(a_el(i, k) * b_el(k, j), 64);
        end loop;
        res(i*N + j) := s;
      end loop;
    end loop;
    return res;
  end function;

  function m_el(ib, jb, pb, e : integer) return u64 is
    variable r, c : integer;
    variable s : u64;
  begin
    r := e / BLK; c := e mod BLK; s := (others => '0');
    for k in 0 to BLK-1 loop
      s := s + resize(a_el(ib*BLK + r, pb*BLK + k) * b_el(pb*BLK + k, jb*BLK + c), 64);
    end loop;
    return s;
  end function;

  function hex(v : std_logic_vector) return string is
  begin
    return to_hstring(v);
  end function;

  function hex(v : unsigned) return string is
  begin
    return to_hstring(std_logic_vector(v));
  end function;

  function us2(ns : integer) return string is
    variable h, f : integer;
  begin
    h := (ns + 5) / 10;  f := h mod 100;          -- hundredths of a microsecond
    if f < 10 then return integer'image(h / 100) & ".0" & integer'image(f);
    else           return integer'image(h / 100) & "."  & integer'image(f); end if;
  end function;
end package body;
