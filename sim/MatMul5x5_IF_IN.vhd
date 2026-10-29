library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity MatMul5x5_PAR_IF is
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;

    -- Input matrices: 25 parallel 64-bit signals each
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

    B0    : in  std_logic_vector(63 downto 0);
    B1    : in  std_logic_vector(63 downto 0);
    B2    : in  std_logic_vector(63 downto 0);
    B3    : in  std_logic_vector(63 downto 0);
    B4    : in  std_logic_vector(63 downto 0);
    B5    : in  std_logic_vector(63 downto 0);
    B6    : in  std_logic_vector(63 downto 0);
    B7    : in  std_logic_vector(63 downto 0);
    B8    : in  std_logic_vector(63 downto 0);
    B9    : in  std_logic_vector(63 downto 0);
    B10   : in  std_logic_vector(63 downto 0);
    B11   : in  std_logic_vector(63 downto 0);
    B12   : in  std_logic_vector(63 downto 0);
    B13   : in  std_logic_vector(63 downto 0);
    B14   : in  std_logic_vector(63 downto 0);
    B15   : in  std_logic_vector(63 downto 0);
    B16   : in  std_logic_vector(63 downto 0);
    B17   : in  std_logic_vector(63 downto 0);
    B18   : in  std_logic_vector(63 downto 0);
    B19   : in  std_logic_vector(63 downto 0);
    B20   : in  std_logic_vector(63 downto 0);
    B21   : in  std_logic_vector(63 downto 0);
    B22   : in  std_logic_vector(63 downto 0);
    B23   : in  std_logic_vector(63 downto 0);
    B24   : in  std_logic_vector(63 downto 0);

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

architecture rtl of MatMul5x5_PAR_IF is

  -- Component declaration for the matrix multiplier
  component MatMul5x5 is
    port (
      clk    : in  std_logic;
      rst    : in  std_logic;
      start  : in  std_logic;
      A_in   : in  std_logic_vector(5*5*64-1 downto 0);
      B_in   : in  std_logic_vector(5*5*64-1 downto 0);
      C_out  : out std_logic_vector(5*5*128-1 downto 0);
      done   : out std_logic
    );
  end component;

  signal A_flat      : std_logic_vector(64*25-1 downto 0);
  signal B_flat      : std_logic_vector(64*25-1 downto 0);
  signal C_flat      : std_logic_vector(128*25-1 downto 0);
  
  signal matmul_start : std_logic;
  signal matmul_done  : std_logic;

  type state_type is (IDLE, COMPUTING, OUTPUT_VALID);
  signal state : state_type := IDLE;

  -- Portable function to pack 25 inputs into flat vector
  function pack25_f(
    A0,A1,A2,A3,A4,A5,A6,A7,A8,A9,
    A10,A11,A12,A13,A14,A15,A16,A17,A18,A19,
    A20,A21,A22,A23,A24 : std_logic_vector(63 downto 0)
  ) return std_logic_vector is
    variable outv : std_logic_vector(64*25-1 downto 0);
  begin
    outv(64*1-1  downto  0*64) := A0;
    outv(64*2-1  downto  1*64) := A1;
    outv(64*3-1  downto  2*64) := A2;
    outv(64*4-1  downto  3*64) := A3;
    outv(64*5-1  downto  4*64) := A4;
    outv(64*6-1  downto  5*64) := A5;
    outv(64*7-1  downto  6*64) := A6;
    outv(64*8-1  downto  7*64) := A7;
    outv(64*9-1  downto  8*64) := A8;
    outv(64*10-1 downto  9*64) := A9;
    outv(64*11-1 downto 10*64) := A10;
    outv(64*12-1 downto 11*64) := A11;
    outv(64*13-1 downto 12*64) := A12;
    outv(64*14-1 downto 13*64) := A13;
    outv(64*15-1 downto 14*64) := A14;
    outv(64*16-1 downto 15*64) := A15;
    outv(64*17-1 downto 16*64) := A16;
    outv(64*18-1 downto 17*64) := A17;
    outv(64*19-1 downto 18*64) := A18;
    outv(64*20-1 downto 19*64) := A19;
    outv(64*21-1 downto 20*64) := A20;
    outv(64*22-1 downto 21*64) := A21;
    outv(64*23-1 downto 22*64) := A22;
    outv(64*24-1 downto 23*64) := A23;
    outv(64*25-1 downto 24*64) := A24;
    return outv;
  end function;

  -- Procedure to unpack flat vector to 25 outputs
  procedure unpack25(
    IN_FLAT  : in  std_logic_vector(128*25-1 downto 0);
    signal C0  : out std_logic_vector(63 downto 0); signal C1  : out std_logic_vector(63 downto 0);
    signal C2  : out std_logic_vector(63 downto 0); signal C3  : out std_logic_vector(63 downto 0);
    signal C4  : out std_logic_vector(63 downto 0); signal C5  : out std_logic_vector(63 downto 0);
    signal C6  : out std_logic_vector(63 downto 0); signal C7  : out std_logic_vector(63 downto 0);
    signal C8  : out std_logic_vector(63 downto 0); signal C9  : out std_logic_vector(63 downto 0);
    signal C10 : out std_logic_vector(63 downto 0); signal C11 : out std_logic_vector(63 downto 0);
    signal C12 : out std_logic_vector(63 downto 0); signal C13 : out std_logic_vector(63 downto 0);
    signal C14 : out std_logic_vector(63 downto 0); signal C15 : out std_logic_vector(63 downto 0);
    signal C16 : out std_logic_vector(63 downto 0); signal C17 : out std_logic_vector(63 downto 0);
    signal C18 : out std_logic_vector(63 downto 0); signal C19 : out std_logic_vector(63 downto 0);
    signal C20 : out std_logic_vector(63 downto 0); signal C21 : out std_logic_vector(63 downto 0);
    signal C22 : out std_logic_vector(63 downto 0); signal C23 : out std_logic_vector(63 downto 0);
    signal C24 : out std_logic_vector(63 downto 0)
  ) is
  begin
    C0  <= IN_FLAT(64*1-1 downto 0*64);
    C1  <= IN_FLAT(64*3-1 downto 2*64);
    C2  <= IN_FLAT(64*5-1 downto 4*64);
    C3  <= IN_FLAT(64*7-1 downto 6*64);
    C4  <= IN_FLAT(64*9-1 downto 8*64);
    C5  <= IN_FLAT(64*11-1 downto 10*64);
    C6  <= IN_FLAT(64*13-1 downto 12*64);
    C7  <= IN_FLAT(64*15-1 downto 14*64);
    C8  <= IN_FLAT(64*17-1 downto 16*64);
    C9  <= IN_FLAT(64*19-1 downto 18*64);
    C10 <= IN_FLAT(64*21-1 downto 20*64);
    C11 <= IN_FLAT(64*23-1 downto 22*64);
    C12 <= IN_FLAT(64*25-1 downto 24*64);
    C13 <= IN_FLAT(64*27-1 downto 26*64);
    C14 <= IN_FLAT(64*29-1 downto 28*64);
    C15 <= IN_FLAT(64*31-1 downto 30*64);
    C16 <= IN_FLAT(64*33-1 downto 32*64);
    C17 <= IN_FLAT(64*35-1 downto 34*64);
    C18 <= IN_FLAT(64*37-1 downto 36*64);
    C19 <= IN_FLAT(64*39-1 downto 38*64);
    C20 <= IN_FLAT(64*41-1 downto 40*64);
    C21 <= IN_FLAT(64*43-1 downto 42*64);
    C22 <= IN_FLAT(64*45-1 downto 44*64);
    C23 <= IN_FLAT(64*47-1 downto 46*64);
    C24 <= IN_FLAT(64*49-1 downto 48*64);
  end procedure;

begin

  -- Instantiate the matrix multiplier
  matmul_inst: MatMul5x5
    port map (
      clk    => clk,
      rst    => rst,
      start  => matmul_start,
      A_in   => A_flat,
      B_in   => B_flat,
      C_out  => C_flat,
      done   => matmul_done
    );

  -- Main control FSM
  process(clk, rst) is
  begin
    if rst = '1' then
      state        <= IDLE;
      matmul_start <= '0';
      ready        <= '1';
      C_valid      <= '0';
      A_flat       <= (others => '0');
      B_flat       <= (others => '0');
      C0 <= (others=>'0'); C1 <= (others=>'0'); C2 <= (others=>'0'); C3 <= (others=>'0'); C4 <= (others=>'0');
      C5 <= (others=>'0'); C6 <= (others=>'0'); C7 <= (others=>'0'); C8 <= (others=>'0'); C9 <= (others=>'0');
      C10 <= (others=>'0'); C11 <= (others=>'0'); C12 <= (others=>'0'); C13 <= (others=>'0'); C14 <= (others=>'0');
      C15 <= (others=>'0'); C16 <= (others=>'0'); C17 <= (others=>'0'); C18 <= (others=>'0'); C19 <= (others=>'0');
      C20 <= (others=>'0'); C21 <= (others=>'0'); C22 <= (others=>'0'); C23 <= (others=>'0'); C24 <= (others=>'0');
      
    elsif rising_edge(clk) then
      -- Default values
      matmul_start <= '0';
      
      case state is
        when IDLE =>
          ready   <= '1';
          C_valid <= '0';
          
          -- Accept new data when valid is asserted
          if valid = '1' then
            -- Pack input matrices into flat vectors
            A_flat <= pack25_f(A0,A1,A2,A3,A4,A5,A6,A7,A8,A9,
                               A10,A11,A12,A13,A14,A15,A16,A17,A18,A19,
                               A20,A21,A22,A23,A24);
            B_flat <= pack25_f(B0,B1,B2,B3,B4,B5,B6,B7,B8,B9,
                               B10,B11,B12,B13,B14,B15,B16,B17,B18,B19,
                               B20,B21,B22,B23,B24);
            
            -- Start the matrix multiplier
            matmul_start <= '1';
            ready        <= '0';
            state        <= COMPUTING;
          end if;

        when COMPUTING =>
          ready <= '0';
          
          -- Wait for matrix multiplier to finish
          if matmul_done = '1' then
            -- Unpack result to output ports
            unpack25(C_flat,
                     C0,C1,C2,C3,C4,C5,C6,C7,C8,C9,
                     C10,C11,C12,C13,C14,C15,C16,C17,C18,C19,
                     C20,C21,C22,C23,C24);
            
            C_valid <= '1';
            state   <= OUTPUT_VALID;
          end if;

        when OUTPUT_VALID =>
          ready <= '0';
          
          -- Wait for downstream to accept the data
          if C_ready = '1' then
            C_valid <= '0';
            ready   <= '1';
            state   <= IDLE;
          end if;

      end case;
    end if;
  end process;

end architecture;