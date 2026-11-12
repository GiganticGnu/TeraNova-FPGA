-- counter.vhd -- practice design for the Vivado simulation guide
-- 8-bit counter with enable; 'tc' is high for one cycle when the count wraps 255 -> 0
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter is
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;                      -- synchronous, active high
    en    : in  std_logic;
    count : out std_logic_vector(7 downto 0);
    tc    : out std_logic);                     -- terminal count
end entity;

architecture rtl of counter is
  signal cnt : unsigned(7 downto 0) := (others => '0');
begin
  process(clk)
  begin
    if rising_edge(clk) then
      tc <= '0';
      if rst = '1' then
        cnt <= (others => '0');
      elsif en = '1' then
        cnt <= cnt + 1;
        if cnt = 255 then
          tc <= '1';
        end if;
      end if;
    end if;
  end process;
  count <= std_logic_vector(cnt);
end architecture;
