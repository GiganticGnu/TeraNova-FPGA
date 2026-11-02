
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity MatMul5x5 is
  Port (
    clk    : in  std_logic;
    rst    : in  std_logic;
    start  : in  std_logic;
    A_in   : in  std_logic_vector(5*5*64-1 downto 0);
    B_in   : in  std_logic_vector(5*5*64-1 downto 0);
    C_out  : out std_logic_vector(5*5*128-1 downto 0);
    done   : out std_logic
  );
end entity;

architecture rtl of MatMul5x5 is
  ---------------------------------------------------------------------------
  -- FSM
  ---------------------------------------------------------------------------
  type state_t is (IDLE, LOAD, COMPUTE, DONE_ST);
  signal state, next_state : state_t;

  ---------------------------------------------------------------------------
  -- Internal matrix storage
  ---------------------------------------------------------------------------
  type mat5x5_64  is array (0 to 4, 0 to 4) of signed(63 downto 0);
  type mat5x5_128 is array (0 to 4, 0 to 4) of signed(127 downto 0);
  signal A : mat5x5_64;
  signal B : mat5x5_64;
  signal C : mat5x5_128;

  ---------------------------------------------------------------------------
  -- Index helper function
  ---------------------------------------------------------------------------
  function slv_to_signed_64(
    vec : std_logic_vector;
    idx : integer
  ) return signed is
    variable x : std_logic_vector(63 downto 0);
  begin
    x := vec(((idx+1)*64)-1 downto (idx*64));
    return signed(x);
  end function;

begin
  ---------------------------------------------------------------------------
  -- FSM Sequential
  ---------------------------------------------------------------------------
  process(clk, rst)
  begin
    if rst = '1' then
      state <= IDLE;
    elsif rising_edge(clk) then
      state <= next_state;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- FSM Combinational
  ---------------------------------------------------------------------------
  process(state, start)
  begin
    next_state <= state;
    case state is
      when IDLE =>
        if start = '1' then
          next_state <= LOAD;
        end if;
      when LOAD =>
        next_state <= COMPUTE;
      when COMPUTE =>
        next_state <= DONE_ST;
      when DONE_ST =>
        next_state <= IDLE;
    end case;
  end process;

  ---------------------------------------------------------------------------
  -- Datapath
  ---------------------------------------------------------------------------
  process(clk)
    variable idx : integer := 0;
    variable acc : signed(127 downto 0);
    variable prod : signed(127 downto 0);
  begin
    if rising_edge(clk) then
      case state is
        ---------------------------------------------------------------------
        when LOAD =>
          -- Load matrix A (flattened input)
          idx := 0;
          for i in 0 to 4 loop
            for j in 0 to 4 loop
              A(i,j) <= slv_to_signed_64(A_in, idx);
              idx := idx + 1;
            end loop;
          end loop;

          -- Load matrix B (flattened input) -- reset idx before B
          idx := 0;
          for i in 0 to 4 loop
            for j in 0 to 4 loop
              B(i,j) <= slv_to_signed_64(B_in, idx);
              idx := idx + 1;
            end loop;
          end loop;

        ---------------------------------------------------------------------
        when COMPUTE =>
          -- C = A × B (integer matrix multiplication)
          for i in 0 to 4 loop
            for j in 0 to 4 loop
              acc := (others => '0');
              for k in 0 to 4 loop
                -- 64×64 => 128-bit product in numeric_std; no need to resize
                prod := A(i,k) * B(k,j);  -- prod is 128 bits
                acc  := acc + prod;
              end loop;
              C(i,j) <= acc;
            end loop;
          end loop;

        when others =>
          null;
      end case;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- Output Flattening
  ---------------------------------------------------------------------------
  process(C)
    variable tmp : std_logic_vector(5*5*128-1 downto 0);
    variable idx : integer := 0;
  begin
    idx := 0;
    for i in 0 to 4 loop
      for j in 0 to 4 loop
        tmp(((idx+1)*128)-1 downto (idx*128)) := std_logic_vector(C(i,j));
        idx := idx + 1;
      end loop;
    end loop;
    C_out <= tmp;
  end process;

  done <= '1' when state = DONE_ST else '0';

end architecture;
