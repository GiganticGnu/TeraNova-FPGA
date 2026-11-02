----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 01/07/2026 02:19:51 PM
-- Design Name: 
-- Module Name: matrix_to_ports - Behavioral
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

entity matrix_to_ports is
    Port ( M_in  : in  STD_LOGIC_VECTOR (1599 downto 0);
           Out0  : out STD_LOGIC_VECTOR (63   downto 0);
           Out1  : out STD_LOGIC_VECTOR (63   downto 0);
           Out2  : out STD_LOGIC_VECTOR (63   downto 0);
           Out3  : out STD_LOGIC_VECTOR (63   downto 0);
           Out4  : out STD_LOGIC_VECTOR (63   downto 0);
           Out5  : out STD_LOGIC_VECTOR (63   downto 0);
           Out6  : out STD_LOGIC_VECTOR (63   downto 0);
           Out7  : out STD_LOGIC_VECTOR (63   downto 0);
           Out8  : out STD_LOGIC_VECTOR (63   downto 0);
           Out9  : out STD_LOGIC_VECTOR (63   downto 0);
           Out10 : out STD_LOGIC_VECTOR (63   downto 0);
           Out11 : out STD_LOGIC_VECTOR (63   downto 0);
           Out12 : out STD_LOGIC_VECTOR (63   downto 0);
           Out13 : out STD_LOGIC_VECTOR (63   downto 0);
           Out14 : out STD_LOGIC_VECTOR (63   downto 0);
           Out15 : out STD_LOGIC_VECTOR (63   downto 0);
           Out16 : out STD_LOGIC_VECTOR (63   downto 0);
           Out17 : out STD_LOGIC_VECTOR (63   downto 0);
           Out18 : out STD_LOGIC_VECTOR (63   downto 0);
           Out19 : out STD_LOGIC_VECTOR (63   downto 0);
           Out20 : out STD_LOGIC_VECTOR (63   downto 0);
           Out21 : out STD_LOGIC_VECTOR (63   downto 0);
           Out22 : out STD_LOGIC_VECTOR (63   downto 0);
           Out23 : out STD_LOGIC_VECTOR (63   downto 0);
           Out24 : out STD_LOGIC_VECTOR (63   downto 0));
end matrix_to_ports;

architecture Behavioral of matrix_to_ports is

begin

    process(M_in)
    begin
        Out0  <= M_in(1599 downto 1536);
        Out1  <= M_in(1535 downto 1472);
        Out2  <= M_in(1471 downto 1408);
        Out3  <= M_in(1407 downto 1344);
        Out4  <= M_in(1343 downto 1280);
        Out5  <= M_in(1279 downto 1216);
        Out6  <= M_in(1215 downto 1152);
        Out7  <= M_in(1151 downto 1088);
        Out8  <= M_in(1087 downto 1024);
        Out9  <= M_in(1023 downto 960 );
        Out10 <= M_in(959  downto 896 );
        Out11 <= M_in(895  downto 832 );
        Out12 <= M_in(831  downto 768 );
        Out13 <= M_in(767  downto 704 );
        Out14 <= M_in(703  downto 640 );
        Out15 <= M_in(639  downto 576 );
        Out16 <= M_in(575  downto 512 );
        Out17 <= M_in(511  downto 448 );
        Out18 <= M_in(447  downto 384 );
        Out19 <= M_in(383  downto 320 );
        Out20 <= M_in(319  downto 256 );
        Out21 <= M_in(255  downto 192 );
        Out22 <= M_in(191  downto 128 );
        Out23 <= M_in(127  downto 64  );
        Out24 <= M_in(63   downto 0   );
    end process;

end Behavioral;
