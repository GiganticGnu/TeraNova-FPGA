library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity matrix_partitioner is
  generic (
    N          : integer := 4;  -- matrix is NxN
    B          : integer := 2;  -- block is BxB
    WORD_WIDTH : integer := 64
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;  -- sync active-high
    start : in  std_logic;  -- enable streaming

    bram_addr_A : out std_logic_vector(10 downto 0);
    bram_addr_B : out std_logic_vector(10 downto 0);

    data_in_highA : in std_logic_vector(31 downto 0);
    data_in_lowA  : in std_logic_vector(31 downto 0);
    data_in_highB : in std_logic_vector(31 downto 0);
    data_in_lowB  : in std_logic_vector(31 downto 0);

    data_out_A : out std_logic_vector((B*B*WORD_WIDTH)-1 downto 0);
    data_out_B : out std_logic_vector((B*B*WORD_WIDTH)-1 downto 0);

    valid : out std_logic;   -- FIX: out, not inout
    ready : in  std_logic
  );
end entity;

architecture rtl of matrix_partitioner is

  constant NUM_BLOCKS : integer := N / B;
  constant MEM_SIZE   : integer := N * N;

  type state_t is (IDLE, ISSUE_ADDR, WAIT1, WAIT2, CAPTURE, OUTPUT);
  signal state : state_t := IDLE;

  signal i_blk : integer range 0 to NUM_BLOCKS-1 := 0;
  signal j_blk : integer range 0 to NUM_BLOCKS-1 := 0;
  signal p_blk : integer range 0 to NUM_BLOCKS-1 := 0;

  signal k     : integer range 0 to (B*B-1) := 0;

  signal addrA : integer range 0 to MEM_SIZE-1 := 0;
  signal addrB : integer range 0 to MEM_SIZE-1 := 0;

  signal wordA64 : std_logic_vector(63 downto 0);
  signal wordB64 : std_logic_vector(63 downto 0);

  type block_array_t is array (0 to B*B-1) of std_logic_vector(63 downto 0);
  signal blockA : block_array_t := (others => (others => '0'));
  signal blockB : block_array_t := (others => (others => '0'));

  signal outA_reg : std_logic_vector((B*B*WORD_WIDTH)-1 downto 0) := (others => '0');
  signal outB_reg : std_logic_vector((B*B*WORD_WIDTH)-1 downto 0) := (others => '0');

  -- FIX: internal valid register
  signal valid_reg : std_logic := '0';

  function calc_addr(brow, bcol, kk : integer) return integer is
    variable r, c : integer;
  begin
    r := kk / B;
    c := kk mod B;
    return (brow*B + r)*N + (bcol*B + c);
  end function;

  function pack_block(words : block_array_t) return std_logic_vector is
    variable v : std_logic_vector((B*B*WORD_WIDTH)-1 downto 0);
  begin
    for idx in 0 to B*B-1 loop
      v((B*B-1-idx)*WORD_WIDTH + WORD_WIDTH-1 downto (B*B-1-idx)*WORD_WIDTH) := words(idx);
    end loop;
    return v;
  end function;

begin

  wordA64 <= data_in_highA & data_in_lowA;
  wordB64 <= data_in_highB & data_in_lowB;

  bram_addr_A <= std_logic_vector(to_unsigned(addrA, bram_addr_A'length));
  bram_addr_B <= std_logic_vector(to_unsigned(addrB, bram_addr_B'length));

  data_out_A <= outA_reg;
  data_out_B <= outB_reg;

  -- drive output port from internal reg
  valid <= valid_reg;

  process(clk)
    variable tmpA : block_array_t;
    variable tmpB : block_array_t;
    variable ni, nj, np : integer;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= IDLE;
        valid_reg <= '0';

        i_blk <= 0; j_blk <= 0; p_blk <= 0; k <= 0;
        addrA <= 0; addrB <= 0;
        blockA <= (others => (others => '0'));
        blockB <= (others => (others => '0'));
        outA_reg <= (others => '0');
        outB_reg <= (others => '0');

      else
        case state is

          when IDLE =>
            valid_reg <= '0';
            if start = '1' then
              i_blk <= 0; j_blk <= 0; p_blk <= 0; k <= 0;
              blockA <= (others => (others => '0'));
              blockB <= (others => (others => '0'));

              addrA <= calc_addr(0, 0, 0);
              addrB <= calc_addr(0, 0, 0);
              state <= ISSUE_ADDR;
            end if;

          when ISSUE_ADDR =>
            state <= WAIT1;

          when WAIT1 =>
            state <= WAIT2;

          when WAIT2 =>
            state <= CAPTURE;

          when CAPTURE =>
            blockA(k) <= wordA64;
            blockB(k) <= wordB64;

            if k = (B*B-1) then
              -- pack including last word
              tmpA := blockA;  tmpB := blockB;
              tmpA(k) := wordA64;
              tmpB(k) := wordB64;

              outA_reg <= pack_block(tmpA);
              outB_reg <= pack_block(tmpB);

              valid_reg <= '1';
              state <= OUTPUT;
            else
              k <= k + 1;

              addrA <= calc_addr(i_blk, p_blk, k + 1);
              addrB <= calc_addr(p_blk, j_blk, k + 1);

              state <= ISSUE_ADDR;
            end if;

          when OUTPUT =>
            -- In OUTPUT, valid_reg is already '1'. Just wait for ready.
            if ready = '1' then
              valid_reg <= '0';

              -- advance p fastest, then j, then i
              ni := i_blk; nj := j_blk; np := p_blk;

              if p_blk < (NUM_BLOCKS-1) then
                np := p_blk + 1;
              else
                np := 0;
                if j_blk < (NUM_BLOCKS-1) then
                  nj := j_blk + 1;
                else
                  nj := 0;
                  if i_blk < (NUM_BLOCKS-1) then
                    ni := i_blk + 1;
                  else
                    ni := 0;
                  end if;
                end if;
              end if;

              i_blk <= ni; j_blk <= nj; p_blk <= np;
              k <= 0;
              blockA <= (others => (others => '0'));
              blockB <= (others => (others => '0'));

              if start = '1' then
                addrA <= calc_addr(ni, np, 0);
                addrB <= calc_addr(np, nj, 0);
                state <= ISSUE_ADDR;
              else
                state <= IDLE;
              end if;
            end if;

        end case;
      end if;
    end if;
  end process;

end architecture;
