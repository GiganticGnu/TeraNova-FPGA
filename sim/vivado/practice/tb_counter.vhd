-- tb_counter.vhd -- self-checking testbench for counter.vhd (VHDL 2008)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_counter is                             -- a testbench has no ports
end entity;

architecture sim of tb_counter is
  constant T_CLK : time := 10 ns;                -- 100 MHz
  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal en       : std_logic := '0';
  signal count    : std_logic_vector(7 downto 0);
  signal tc       : std_logic;
  signal finished : boolean := false;
begin
  -- 1. clock: runs until the stimulus sets 'finished'
  clk <= not clk after T_CLK / 2 when not finished;

  -- 2. the unit under test
  uut : entity work.counter
    port map (clk => clk, rst => rst, en => en, count => count, tc => tc);

  -- 3. stimulus and checks
  process
    variable errors : integer := 0;
  begin
    rst <= '1';
    wait for 3 * T_CLK;
    wait until rising_edge(clk);
    rst <= '0';

    -- count 10 times, check the value
    en <= '1';
    for i in 1 to 10 loop
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;                               -- let the outputs settle after the edge
    if unsigned(count) /= 10 then
      report "count is " & integer'image(to_integer(unsigned(count))) & ", expected 10" severity error;
      errors := errors + 1;
    end if;

    -- pause: the value must hold
    en <= '0';
    for i in 1 to 5 loop wait until rising_edge(clk); end loop;
    wait for 1 ns;
    assert unsigned(count) = 10 report "count changed while en = '0'" severity error;

    -- run to the wrap-around and check the terminal count pulse
    en <= '1';
    wait until tc = '1' for 300 * T_CLK;
    if tc /= '1' then
      report "no terminal count pulse" severity error;
      errors := errors + 1;
    end if;

    if errors = 0 then
      report "TEST PASSED";
    else
      report "TEST FAILED with " & integer'image(errors) & " error(s)" severity error;
    end if;
    finished <= true;                            -- 4. stop the clock: simulation ends
    wait;
  end process;
end architecture;
