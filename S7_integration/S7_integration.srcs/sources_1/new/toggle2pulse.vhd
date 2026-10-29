----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 01/14/2026 11:01:47 AM
-- Design Name: 
-- Module Name: toggle2pulse - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity toggle2pulse is
    Generic ( pulse_width :     integer := 4 );
    Port (    toggle      : in  STD_LOGIC;
              pulse       : out STD_LOGIC;
              clk         : in  STD_LOGIC;
              rst         : in  STD_LOGIC);
end toggle2pulse;

architecture Behavioral of toggle2pulse is

    signal last_toggle : STD_LOGIC;
    signal cnt         : integer range 0 to pulse_width := 0;

begin

    process(clk, rst) 
    begin
        if rst = '1' then
            last_toggle <= '0';
            cnt         <=  0;
            pulse       <= '0';
        elsif rising_edge(clk) then
            if (toggle = not last_toggle) then
                last_toggle <= toggle;
                cnt         <= pulse_width;
            elsif (cnt > 0) then
                cnt <= cnt - 1;
            end if;

            if (cnt > 0) then
                pulse <= '1';
            else
                pulse <= '0';
            end if;
        end if;
    end process;

end Behavioral;
