library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity MatMul5x5_Accumulator is
  generic (
    NUM_ACCUMULATIONS : positive := 5
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;

    -- Input matrix: 25 parallel 64-bit signals
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

    -- Output matrix
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
end entity;

architecture rtl of MatMul5x5_Accumulator is

  -- Accumulator registers (128-bit to hold sums of up to 5 64-bit values)
  signal acc0  : std_logic_vector(127 downto 0);
  signal acc1  : std_logic_vector(127 downto 0);
  signal acc2  : std_logic_vector(127 downto 0);
  signal acc3  : std_logic_vector(127 downto 0);
  signal acc4  : std_logic_vector(127 downto 0);
  signal acc5  : std_logic_vector(127 downto 0);
  signal acc6  : std_logic_vector(127 downto 0);
  signal acc7  : std_logic_vector(127 downto 0);
  signal acc8  : std_logic_vector(127 downto 0);
  signal acc9  : std_logic_vector(127 downto 0);
  signal acc10 : std_logic_vector(127 downto 0);
  signal acc11 : std_logic_vector(127 downto 0);
  signal acc12 : std_logic_vector(127 downto 0);
  signal acc13 : std_logic_vector(127 downto 0);
  signal acc14 : std_logic_vector(127 downto 0);
  signal acc15 : std_logic_vector(127 downto 0);
  signal acc16 : std_logic_vector(127 downto 0);
  signal acc17 : std_logic_vector(127 downto 0);
  signal acc18 : std_logic_vector(127 downto 0);
  signal acc19 : std_logic_vector(127 downto 0);
  signal acc20 : std_logic_vector(127 downto 0);
  signal acc21 : std_logic_vector(127 downto 0);
  signal acc22 : std_logic_vector(127 downto 0);
  signal acc23 : std_logic_vector(127 downto 0);
  signal acc24 : std_logic_vector(127 downto 0);

  -- Matrix counter: counts inputs from 0 to NUM_ACCUMULATIONS-1
  signal matrix_count : unsigned(31 downto 0);

  type state_type is (IDLE, ACCUMULATING, OUTPUT_VALID);
  signal state : state_type := IDLE;

  -- Function to add two 64-bit values and store in 128-bit accumulator
  function add_to_acc(acc : std_logic_vector(127 downto 0); 
                      val : std_logic_vector(63 downto 0)) 
    return std_logic_vector is
    variable acc_unsigned : unsigned(127 downto 0);
    variable val_unsigned : unsigned(127 downto 0);
    variable result       : unsigned(127 downto 0);
  begin
    acc_unsigned := unsigned(acc);
    val_unsigned := resize(unsigned(val), 128);
    result := acc_unsigned + val_unsigned;
    return std_logic_vector(result);
  end function;

begin

  -- Main control FSM
  process(clk, rst) is
  begin
    if rst = '1' then
      state        <= IDLE;
      ready        <= '1';
      C_valid      <= '0';
      matrix_count <= (others => '0');
      
      acc0  <= (others => '0'); acc1  <= (others => '0'); acc2  <= (others => '0');
      acc3  <= (others => '0'); acc4  <= (others => '0'); acc5  <= (others => '0');
      acc6  <= (others => '0'); acc7  <= (others => '0'); acc8  <= (others => '0');
      acc9  <= (others => '0'); acc10 <= (others => '0'); acc11 <= (others => '0');
      acc12 <= (others => '0'); acc13 <= (others => '0'); acc14 <= (others => '0');
      acc15 <= (others => '0'); acc16 <= (others => '0'); acc17 <= (others => '0');
      acc18 <= (others => '0'); acc19 <= (others => '0'); acc20 <= (others => '0');
      acc21 <= (others => '0'); acc22 <= (others => '0'); acc23 <= (others => '0');
      acc24 <= (others => '0');
      
    elsif rising_edge(clk) then
      
      case state is
        when IDLE =>
          ready   <= '1';
          C_valid <= '0';
          
          -- Accept new data when valid is asserted
          if valid = '1' then
            -- Add input matrix to accumulators
            acc0  <= add_to_acc(acc0,  A0);
            acc1  <= add_to_acc(acc1,  A1);
            acc2  <= add_to_acc(acc2,  A2);
            acc3  <= add_to_acc(acc3,  A3);
            acc4  <= add_to_acc(acc4,  A4);
            acc5  <= add_to_acc(acc5,  A5);
            acc6  <= add_to_acc(acc6,  A6);
            acc7  <= add_to_acc(acc7,  A7);
            acc8  <= add_to_acc(acc8,  A8);
            acc9  <= add_to_acc(acc9,  A9);
            acc10 <= add_to_acc(acc10, A10);
            acc11 <= add_to_acc(acc11, A11);
            acc12 <= add_to_acc(acc12, A12);
            acc13 <= add_to_acc(acc13, A13);
            acc14 <= add_to_acc(acc14, A14);
            acc15 <= add_to_acc(acc15, A15);
            acc16 <= add_to_acc(acc16, A16);
            acc17 <= add_to_acc(acc17, A17);
            acc18 <= add_to_acc(acc18, A18);
            acc19 <= add_to_acc(acc19, A19);
            acc20 <= add_to_acc(acc20, A20);
            acc21 <= add_to_acc(acc21, A21);
            acc22 <= add_to_acc(acc22, A22);
            acc23 <= add_to_acc(acc23, A23);
            acc24 <= add_to_acc(acc24, A24);
            
            -- Increment matrix counter
            if matrix_count = NUM_ACCUMULATIONS - 1 then
              -- Last matrix received, prepare to output
              state   <= OUTPUT_VALID;
              ready   <= '0';
              C_valid <= '1';
            else
              -- More matrices to accumulate
              matrix_count <= matrix_count + 1;
              state        <= ACCUMULATING;
              ready        <= '0';
            end if;
          end if;

        when ACCUMULATING =>
          ready   <= '1';
          C_valid <= '0';
          
          -- Accept next data when valid is asserted
          if valid = '1' then
            -- Add input matrix to accumulators
            acc0  <= add_to_acc(acc0,  A0);
            acc1  <= add_to_acc(acc1,  A1);
            acc2  <= add_to_acc(acc2,  A2);
            acc3  <= add_to_acc(acc3,  A3);
            acc4  <= add_to_acc(acc4,  A4);
            acc5  <= add_to_acc(acc5,  A5);
            acc6  <= add_to_acc(acc6,  A6);
            acc7  <= add_to_acc(acc7,  A7);
            acc8  <= add_to_acc(acc8,  A8);
            acc9  <= add_to_acc(acc9,  A9);
            acc10 <= add_to_acc(acc10, A10);
            acc11 <= add_to_acc(acc11, A11);
            acc12 <= add_to_acc(acc12, A12);
            acc13 <= add_to_acc(acc13, A13);
            acc14 <= add_to_acc(acc14, A14);
            acc15 <= add_to_acc(acc15, A15);
            acc16 <= add_to_acc(acc16, A16);
            acc17 <= add_to_acc(acc17, A17);
            acc18 <= add_to_acc(acc18, A18);
            acc19 <= add_to_acc(acc19, A19);
            acc20 <= add_to_acc(acc20, A20);
            acc21 <= add_to_acc(acc21, A21);
            acc22 <= add_to_acc(acc22, A22);
            acc23 <= add_to_acc(acc23, A23);
            acc24 <= add_to_acc(acc24, A24);
            
            -- Increment matrix counter
            if matrix_count = NUM_ACCUMULATIONS - 1 then
              -- Last matrix received, prepare to output
              state   <= OUTPUT_VALID;
              ready   <= '0';
              C_valid <= '1';
            else
              -- More matrices to accumulate
              matrix_count <= matrix_count + 1;
            end if;
          end if;

        when OUTPUT_VALID =>
          ready <= '0';
          
          -- Wait for downstream to accept the data
          if C_ready = '1' then
            C_valid      <= '0';
            ready        <= '1';
            state        <= IDLE;
            matrix_count <= (others => '0');
            
            -- Reset accumulators for next batch
            acc0  <= (others => '0'); acc1  <= (others => '0'); acc2  <= (others => '0');
            acc3  <= (others => '0'); acc4  <= (others => '0'); acc5  <= (others => '0');
            acc6  <= (others => '0'); acc7  <= (others => '0'); acc8  <= (others => '0');
            acc9  <= (others => '0'); acc10 <= (others => '0'); acc11 <= (others => '0');
            acc12 <= (others => '0'); acc13 <= (others => '0'); acc14 <= (others => '0');
            acc15 <= (others => '0'); acc16 <= (others => '0'); acc17 <= (others => '0');
            acc18 <= (others => '0'); acc19 <= (others => '0'); acc20 <= (others => '0');
            acc21 <= (others => '0'); acc22 <= (others => '0'); acc23 <= (others => '0');
            acc24 <= (others => '0');
          end if;

      end case;
    end if;
  end process;

  -- Output assignments (truncate 128-bit accumulators to 64-bit outputs)
  C0  <= acc0(63 downto 0);   C1  <= acc1(63 downto 0);   C2  <= acc2(63 downto 0);
  C3  <= acc3(63 downto 0);   C4  <= acc4(63 downto 0);   C5  <= acc5(63 downto 0);
  C6  <= acc6(63 downto 0);   C7  <= acc7(63 downto 0);   C8  <= acc8(63 downto 0);
  C9  <= acc9(63 downto 0);   C10 <= acc10(63 downto 0);  C11 <= acc11(63 downto 0);
  C12 <= acc12(63 downto 0);  C13 <= acc13(63 downto 0);  C14 <= acc14(63 downto 0);
  C15 <= acc15(63 downto 0);  C16 <= acc16(63 downto 0);  C17 <= acc17(63 downto 0);
  C18 <= acc18(63 downto 0);  C19 <= acc19(63 downto 0);  C20 <= acc20(63 downto 0);
  C21 <= acc21(63 downto 0);  C22 <= acc22(63 downto 0);  C23 <= acc23(63 downto 0);
  C24 <= acc24(63 downto 0);

end architecture;