library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_MatMul5x5_Accumulator is
end entity;

architecture tb of tb_MatMul5x5_Accumulator is

  -- Test configuration
  constant NUM_ACCUMULATIONS : positive := 5;

  -- Component declaration
  component MatMul5x5_Accumulator is
    generic (
      NUM_ACCUMULATIONS : positive := 5
    );
    port (
      clk   : in  std_logic;
      rst   : in  std_logic;
      A0    : in  std_logic_vector(63 downto 0);
      A1    : in  std_logic_vector(63 downto 0);
      A2    : in  std_logic_vector(63 downto 0);
      A3    : in  std_logic_vector(63 downto 0);
      A4    : in  std_logic_vector(63 downto 0);
      A5    : in  std_logic_vector(63 downto 0);
      A6    : in  std_logic_vector(63 downto 0);
      A7    : in  std_logic_vector(63 downto 0);
      A8    : in  std_logic_vector(63 downto 0);
      A9    : in  std_logic_vector(63 downto 0);
      A10   : in  std_logic_vector(63 downto 0);
      A11   : in  std_logic_vector(63 downto 0);
      A12   : in  std_logic_vector(63 downto 0);
      A13   : in  std_logic_vector(63 downto 0);
      A14   : in  std_logic_vector(63 downto 0);
      A15   : in  std_logic_vector(63 downto 0);
      A16   : in  std_logic_vector(63 downto 0);
      A17   : in  std_logic_vector(63 downto 0);
      A18   : in  std_logic_vector(63 downto 0);
      A19   : in  std_logic_vector(63 downto 0);
      A20   : in  std_logic_vector(63 downto 0);
      A21   : in  std_logic_vector(63 downto 0);
      A22   : in  std_logic_vector(63 downto 0);
      A23   : in  std_logic_vector(63 downto 0);
      A24   : in  std_logic_vector(63 downto 0);
      valid : in  std_logic;
      ready : out std_logic;
      C0    : out std_logic_vector(63 downto 0);
      C1    : out std_logic_vector(63 downto 0);
      C2    : out std_logic_vector(63 downto 0);
      C3    : out std_logic_vector(63 downto 0);
      C4    : out std_logic_vector(63 downto 0);
      C5    : out std_logic_vector(63 downto 0);
      C6    : out std_logic_vector(63 downto 0);
      C7    : out std_logic_vector(63 downto 0);
      C8    : out std_logic_vector(63 downto 0);
      C9    : out std_logic_vector(63 downto 0);
      C10   : out std_logic_vector(63 downto 0);
      C11   : out std_logic_vector(63 downto 0);
      C12   : out std_logic_vector(63 downto 0);
      C13   : out std_logic_vector(63 downto 0);
      C14   : out std_logic_vector(63 downto 0);
      C15   : out std_logic_vector(63 downto 0);
      C16   : out std_logic_vector(63 downto 0);
      C17   : out std_logic_vector(63 downto 0);
      C18   : out std_logic_vector(63 downto 0);
      C19   : out std_logic_vector(63 downto 0);
      C20   : out std_logic_vector(63 downto 0);
      C21   : out std_logic_vector(63 downto 0);
      C22   : out std_logic_vector(63 downto 0);
      C23   : out std_logic_vector(63 downto 0);
      C24   : out std_logic_vector(63 downto 0);
      C_valid : out std_logic;
      C_ready : in  std_logic
    );
  end component;

  -- Test signals
  signal clk      : std_logic := '0';
  signal rst      : std_logic := '0';
  signal valid    : std_logic := '0';
  signal ready    : std_logic;
  signal C_valid  : std_logic;
  signal C_ready  : std_logic := '0';

  -- Input signals
  signal A0, A1, A2, A3, A4, A5, A6, A7, A8, A9       : std_logic_vector(63 downto 0) := (others => '0');
  signal A10, A11, A12, A13, A14, A15, A16, A17, A18, A19 : std_logic_vector(63 downto 0) := (others => '0');
  signal A20, A21, A22, A23, A24 : std_logic_vector(63 downto 0) := (others => '0');

  -- Output signals
  signal C0, C1, C2, C3, C4, C5, C6, C7, C8, C9       : std_logic_vector(63 downto 0);
  signal C10, C11, C12, C13, C14, C15, C16, C17, C18, C19 : std_logic_vector(63 downto 0);
  signal C20, C21, C22, C23, C24 : std_logic_vector(63 downto 0);

  -- Clock period
  constant CLK_PERIOD : time := 10 ns;

begin

  -- Clock generation
  clk <= not clk after CLK_PERIOD/2;
  
  process(ready)
  begin
  
  if(ready = '1') then
    valid <= '1';
  else
    valid <= '0';
  end if;
  
    if(C_valid = '1') then
    C_ready <= '1';
  else
    C_ready <= '0';
  end if;
  
  end process;

  -- Instantiate DUT
  dut: MatMul5x5_Accumulator
    generic map (
      NUM_ACCUMULATIONS => NUM_ACCUMULATIONS
    )
    port map (
      clk    => clk,
      rst    => rst,
      A0     => A0,  A1  => A1,  A2  => A2,  A3  => A3,  A4  => A4,
      A5     => A5,  A6  => A6,  A7  => A7,  A8  => A8,  A9  => A9,
      A10    => A10, A11 => A11, A12 => A12, A13 => A13, A14 => A14,
      A15    => A15, A16 => A16, A17 => A17, A18 => A18, A19 => A19,
      A20    => A20, A21 => A21, A22 => A22, A23 => A23, A24 => A24,
      valid  => valid,
      ready  => ready,
      C0     => C0,  C1  => C1,  C2  => C2,  C3  => C3,  C4  => C4,
      C5     => C5,  C6  => C6,  C7  => C7,  C8  => C8,  C9  => C9,
      C10    => C10, C11 => C11, C12 => C12, C13 => C13, C14 => C14,
      C15    => C15, C16 => C16, C17 => C17, C18 => C18, C19 => C19,
      C20    => C20, C21 => C21, C22 => C22, C23 => C23, C24 => C24,
      C_valid => C_valid,
      C_ready => C_ready
    );

  -- Main test process
  test_process: process
    variable errors : integer := 0;
    variable matrix_cnt : integer;
  begin
    report "=== Matrix Accumulator Testbench Start ===";
    report "Configuration: NUM_ACCUMULATIONS = " & integer'image(NUM_ACCUMULATIONS);

    -- Initial reset
    rst <= '1';
    wait for CLK_PERIOD * 2;
    rst <= '0';
    wait for CLK_PERIOD * 2;

    -- TEST 1: All elements = 1
    report "TEST 1: Basic operation with all elements = 1";
    
    for matrix_cnt in 0 to NUM_ACCUMULATIONS-1 loop
      -- Set all inputs to 1
      A0  <= x"0000000000000001";
      A1  <= x"0000000000000001";
      A2  <= x"0000000000000001";
      A3  <= x"0000000000000001";
      A4  <= x"0000000000000001";
      A5  <= x"0000000000000001";
      A6  <= x"0000000000000001";
      A7  <= x"0000000000000001";
      A8  <= x"0000000000000001";
      A9  <= x"0000000000000001";
      A10 <= x"0000000000000001";
      A11 <= x"0000000000000001";
      A12 <= x"0000000000000001";
      A13 <= x"0000000000000001";
      A14 <= x"0000000000000001";
      A15 <= x"0000000000000001";
      A16 <= x"0000000000000001";
      A17 <= x"0000000000000001";
      A18 <= x"0000000000000001";
      A19 <= x"0000000000000001";
      A20 <= x"0000000000000001";
      A21 <= x"0000000000000001";
      A22 <= x"0000000000000001";
      A23 <= x"0000000000000001";
      A24 <= x"0000000000000001";
      
      -- Wait for ready and send data

      wait for CLK_PERIOD * 2;
    end loop;

    
    -- Check results (should all be NUM_ACCUMULATIONS = 5)
    if C0 /= x"0000000000000005" or C1 /= x"0000000000000005" then
      report "TEST 1 FAILED";
      errors := errors + 1;
    else
      report "TEST 1 PASSED";
    end if;


    -- TEST 2: Non-uniform values
    report "TEST 2: Non-uniform values (element index as value)";
    
    for matrix_cnt in 0 to NUM_ACCUMULATIONS-1 loop
      A0  <= std_logic_vector(to_unsigned(0, 64));
      A1  <= std_logic_vector(to_unsigned(1, 64));
      A2  <= std_logic_vector(to_unsigned(2, 64));
      A3  <= std_logic_vector(to_unsigned(3, 64));
      A4  <= std_logic_vector(to_unsigned(4, 64));
      A5  <= std_logic_vector(to_unsigned(5, 64));
      A6  <= std_logic_vector(to_unsigned(6, 64));
      A7  <= std_logic_vector(to_unsigned(7, 64));
      A8  <= std_logic_vector(to_unsigned(8, 64));
      A9  <= std_logic_vector(to_unsigned(9, 64));
      A10 <= std_logic_vector(to_unsigned(10, 64));
      A11 <= std_logic_vector(to_unsigned(11, 64));
      A12 <= std_logic_vector(to_unsigned(12, 64));
      A13 <= std_logic_vector(to_unsigned(13, 64));
      A14 <= std_logic_vector(to_unsigned(14, 64));
      A15 <= std_logic_vector(to_unsigned(15, 64));
      A16 <= std_logic_vector(to_unsigned(16, 64));
      A17 <= std_logic_vector(to_unsigned(17, 64));
      A18 <= std_logic_vector(to_unsigned(18, 64));
      A19 <= std_logic_vector(to_unsigned(19, 64));
      A20 <= std_logic_vector(to_unsigned(20, 64));
      A21 <= std_logic_vector(to_unsigned(21, 64));
      A22 <= std_logic_vector(to_unsigned(22, 64));
      A23 <= std_logic_vector(to_unsigned(23, 64));
      A24 <= std_logic_vector(to_unsigned(24, 64));
      
      wait until ready = '1';

      wait for CLK_PERIOD * 2;
    end loop;
    
    -- Check a few results (element_index * NUM_ACCUMULATIONS)
    if C0 /= std_logic_vector(to_unsigned(0, 64)) or 
       C5 /= std_logic_vector(to_unsigned(5 * NUM_ACCUMULATIONS, 64)) then
      report "TEST 2 FAILED";
      errors := errors + 1;
    else
      report "TEST 2 PASSED";
    end if;


    -- Final report
    report "=== Test Complete ===";
    if errors = 0 then
      report "All tests PASSED";
    else
      report "Tests FAILED with " & integer'image(errors) & " errors";
    end if;

    wait;
  end process;

end architecture;