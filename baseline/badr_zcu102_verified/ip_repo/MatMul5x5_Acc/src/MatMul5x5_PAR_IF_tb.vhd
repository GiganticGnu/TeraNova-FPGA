library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity MatMul5x5_PAR_IF_tb is
end entity;

architecture tb of MatMul5x5_PAR_IF_tb is

  -- Component under test
  component MatMul5x5_PAR_IF
    port (
      clk     : in  std_logic;
      rst     : in  std_logic;
      A0      : in  std_logic_vector(63 downto 0);
      A1      : in  std_logic_vector(63 downto 0);
      A2      : in  std_logic_vector(63 downto 0);
      A3      : in  std_logic_vector(63 downto 0);
      A4      : in  std_logic_vector(63 downto 0);
      A5      : in  std_logic_vector(63 downto 0);
      A6      : in  std_logic_vector(63 downto 0);
      A7      : in  std_logic_vector(63 downto 0);
      A8      : in  std_logic_vector(63 downto 0);
      A9      : in  std_logic_vector(63 downto 0);
      A10     : in  std_logic_vector(63 downto 0);
      A11     : in  std_logic_vector(63 downto 0);
      A12     : in  std_logic_vector(63 downto 0);
      A13     : in  std_logic_vector(63 downto 0);
      A14     : in  std_logic_vector(63 downto 0);
      A15     : in  std_logic_vector(63 downto 0);
      A16     : in  std_logic_vector(63 downto 0);
      A17     : in  std_logic_vector(63 downto 0);
      A18     : in  std_logic_vector(63 downto 0);
      A19     : in  std_logic_vector(63 downto 0);
      A20     : in  std_logic_vector(63 downto 0);
      A21     : in  std_logic_vector(63 downto 0);
      A22     : in  std_logic_vector(63 downto 0);
      A23     : in  std_logic_vector(63 downto 0);
      A24     : in  std_logic_vector(63 downto 0);
      B0      : in  std_logic_vector(63 downto 0);
      B1      : in  std_logic_vector(63 downto 0);
      B2      : in  std_logic_vector(63 downto 0);
      B3      : in  std_logic_vector(63 downto 0);
      B4      : in  std_logic_vector(63 downto 0);
      B5      : in  std_logic_vector(63 downto 0);
      B6      : in  std_logic_vector(63 downto 0);
      B7      : in  std_logic_vector(63 downto 0);
      B8      : in  std_logic_vector(63 downto 0);
      B9      : in  std_logic_vector(63 downto 0);
      B10     : in  std_logic_vector(63 downto 0);
      B11     : in  std_logic_vector(63 downto 0);
      B12     : in  std_logic_vector(63 downto 0);
      B13     : in  std_logic_vector(63 downto 0);
      B14     : in  std_logic_vector(63 downto 0);
      B15     : in  std_logic_vector(63 downto 0);
      B16     : in  std_logic_vector(63 downto 0);
      B17     : in  std_logic_vector(63 downto 0);
      B18     : in  std_logic_vector(63 downto 0);
      B19     : in  std_logic_vector(63 downto 0);
      B20     : in  std_logic_vector(63 downto 0);
      B21     : in  std_logic_vector(63 downto 0);
      B22     : in  std_logic_vector(63 downto 0);
      B23     : in  std_logic_vector(63 downto 0);
      B24     : in  std_logic_vector(63 downto 0);
      valid   : in  std_logic;
      ready   : out std_logic;
      C0      : out std_logic_vector(63 downto 0);
      C1      : out std_logic_vector(63 downto 0);
      C2      : out std_logic_vector(63 downto 0);
      C3      : out std_logic_vector(63 downto 0);
      C4      : out std_logic_vector(63 downto 0);
      C5      : out std_logic_vector(63 downto 0);
      C6      : out std_logic_vector(63 downto 0);
      C7      : out std_logic_vector(63 downto 0);
      C8      : out std_logic_vector(63 downto 0);
      C9      : out std_logic_vector(63 downto 0);
      C10     : out std_logic_vector(63 downto 0);
      C11     : out std_logic_vector(63 downto 0);
      C12     : out std_logic_vector(63 downto 0);
      C13     : out std_logic_vector(63 downto 0);
      C14     : out std_logic_vector(63 downto 0);
      C15     : out std_logic_vector(63 downto 0);
      C16     : out std_logic_vector(63 downto 0);
      C17     : out std_logic_vector(63 downto 0);
      C18     : out std_logic_vector(63 downto 0);
      C19     : out std_logic_vector(63 downto 0);
      C20     : out std_logic_vector(63 downto 0);
      C21     : out std_logic_vector(63 downto 0);
      C22     : out std_logic_vector(63 downto 0);
      C23     : out std_logic_vector(63 downto 0);
      C24     : out std_logic_vector(63 downto 0);
      C_valid : out std_logic;
      C_ready : in  std_logic
    );
  end component;

  -- Signals
  signal clk_tb     : std_logic := '0';
  signal rst_tb     : std_logic := '1';
  signal valid_tb   : std_logic := '0';
  signal ready_tb   : std_logic;
  signal C_valid_tb : std_logic := '0';
  signal C_ready_tb : std_logic := '0';


  -- Arrays for inputs
  type vec64_array is array (0 to 24) of std_logic_vector(63 downto 0);
  signal A_array : vec64_array;
  signal B_array : vec64_array;

  -- Outputs
  type vec128_array is array (0 to 24) of std_logic_vector(63 downto 0);
  signal C_array : vec128_array;

begin

  -- Clock generation
  clk_process : process
  begin
    while true loop
      clk_tb <= '0';
      wait for 5 ns;
      clk_tb <= '1';
      wait for 5 ns;
    end loop;
  end process;

  -- Instantiate DUT
  dut: MatMul5x5_PAR_IF
    port map (
      clk     => clk_tb,
      rst     => rst_tb,
      -- Inputs
      A0 => A_array(0),  A1 => A_array(1),  A2 => A_array(2),  A3 => A_array(3),  A4 => A_array(4),
      A5 => A_array(5),  A6 => A_array(6),  A7 => A_array(7),  A8 => A_array(8),  A9 => A_array(9),
      A10 => A_array(10),A11 => A_array(11),A12 => A_array(12),A13 => A_array(13),A14 => A_array(14),
      A15 => A_array(15),A16 => A_array(16),A17 => A_array(17),A18 => A_array(18),A19 => A_array(19),
      A20 => A_array(20),A21 => A_array(21),A22 => A_array(22),A23 => A_array(23),A24 => A_array(24),
      B0 => B_array(0),  B1 => B_array(1),  B2 => B_array(2),  B3 => B_array(3),  B4 => B_array(4),
      B5 => B_array(5),  B6 => B_array(6),  B7 => B_array(7),  B8 => B_array(8),  B9 => B_array(9),
      B10 => B_array(10),B11 => B_array(11),B12 => B_array(12),B13 => B_array(13),B14 => B_array(14),
      B15 => B_array(15),B16 => B_array(16),B17 => B_array(17),B18 => B_array(18),B19 => B_array(19),
      B20 => B_array(20),B21 => B_array(21),B22 => B_array(22),B23 => B_array(23),B24 => B_array(24),
      valid   => valid_tb,
      ready   => ready_tb,
      -- Outputs
      C0  => C_array(0),  C1  => C_array(1),  C2  => C_array(2),  C3  => C_array(3),  C4  => C_array(4),
      C5  => C_array(5),  C6  => C_array(6),  C7  => C_array(7),  C8  => C_array(8),  C9  => C_array(9),
      C10 => C_array(10), C11 => C_array(11), C12 => C_array(12), C13 => C_array(13), C14 => C_array(14),
      C15 => C_array(15), C16 => C_array(16), C17 => C_array(17), C18 => C_array(18), C19 => C_array(19),
      C20 => C_array(20), C21 => C_array(21), C22 => C_array(22), C23 => C_array(23), C24 => C_array(24),
      C_valid => C_valid_tb,
      C_ready => C_ready_tb
    );

  -- Test process
  stim_proc : process
  begin
    -- Reset
    rst_tb <= '1';
    wait for 20 ns;
    rst_tb <= '0';
    wait for 20 ns;

    -- Initialize matrices
    for i in 0 to 24 loop
      A_array(i) <= std_logic_vector(to_unsigned(i+1,64));
      B_array(i) <= std_logic_vector(to_unsigned((i+1)*2,64));
    end loop;

    -- Apply valid and wait for ready
    valid_tb <= '1';
    wait until ready_tb = '1';
    valid_tb <= '0';

    -- Wait for C_valid to go high
    wait until C_valid_tb = '1';
    report "Matrix multiplication done, C_valid asserted";

    -- Simulate downstream ready
    C_ready_tb <= '1';
    wait until C_valid_tb = '0';
    C_ready_tb <= '0';
    report "C data accepted by downstream";

    -- Wait a few cycles
    wait for 50 ns;

    -- Finish simulation
    report "Testbench finished";
    wait;
  end process;

end architecture;
