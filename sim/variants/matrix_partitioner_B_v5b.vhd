-- =============================================================================
-- matrix_partitioner_B  --  variant v5b, core revision 5 (29 Oct 2026)
-- Simulated with tb_chain / tb_chain_perf / tb_chain_rtl (sim/run_variants.py): all PASS
--
-- Pipelined fetch: a new BRAM address is issued EVERY cycle, and the data for
-- an address is captured two clock edges after the address was set
-- (address register -> BRAM read latency 1 -> capture). One block pair
-- (25 elements of A and of B) takes 27 cycles instead of 101:
--   1 edge to issue element 0, 24 edges to issue elements 1..24,
--   2 edges until element 24 is captured, 1 edge for the output handshake.
--
-- Same entity name, generics, ports and block order (i, j, p with p fastest)
-- as revision 4: drop-in replacement. Output packing is unchanged.
-- Assumes BRAM port B read latency = 1 (no output register), as in the design.
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity matrix_partitioner_B is
  generic (
    N          : integer := 50; -- matrix is NxN
    B          : integer := 5;  -- block is BxB
    WORD_WIDTH : integer := 64
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;  -- sync active-high
    start : in  std_logic;  -- can be a 1-cycle pulse

    bram_addr_A : out std_logic_vector(11 downto 0);
    bram_addr_B : out std_logic_vector(11 downto 0);

    data_in_highA : in std_logic_vector(31 downto 0);
    data_in_lowA  : in std_logic_vector(31 downto 0);
    data_in_highB : in std_logic_vector(31 downto 0);
    data_in_lowB  : in std_logic_vector(31 downto 0);

    data_out_A : out std_logic_vector((B*B*WORD_WIDTH)-1 downto 0);
    data_out_B : out std_logic_vector((B*B*WORD_WIDTH)-1 downto 0);

    valid : out std_logic;
    ready : in  std_logic
  );
end entity;

architecture rtl of matrix_partitioner_B is
  constant NUM_BLOCKS : integer := N / B;
  constant MEM_SIZE   : integer := N * N;
  constant LAST_K     : integer := B*B - 1;

  type state_t is (IDLE, FETCH, OUTPUT);
  signal state : state_t := IDLE;

  -- current block triple
  signal i_blk : integer range 0 to NUM_BLOCKS-1 := 0;
  signal j_blk : integer range 0 to NUM_BLOCKS-1 := 0;
  signal p_blk : integer range 0 to NUM_BLOCKS-1 := 0;

  -- issue side: next element to issue (row/col inside the block) and count
  signal iss_k   : integer range 0 to B*B := 0;
  signal iss_row : integer range 0 to B-1 := 0;
  signal iss_col : integer range 0 to B-1 := 0;

  -- 2-stage valid/index pipeline from "address set" to "data valid"
  signal v1, v2     : std_logic := '0';
  signal idx1, idx2 : integer range 0 to LAST_K := 0;

  signal addrA : integer range 0 to MEM_SIZE-1 := 0;
  signal addrB : integer range 0 to MEM_SIZE-1 := 0;

  signal wordA64 : std_logic_vector(63 downto 0);
  signal wordB64 : std_logic_vector(63 downto 0);

  type block_array_t is array (0 to B*B-1) of std_logic_vector(63 downto 0);
  signal blockA : block_array_t := (others => (others => '0'));
  signal blockB : block_array_t := (others => (others => '0'));

  signal outA_reg  : std_logic_vector((B*B*WORD_WIDTH)-1 downto 0) := (others => '0');
  signal outB_reg  : std_logic_vector((B*B*WORD_WIDTH)-1 downto 0) := (others => '0');
  signal valid_reg : std_logic := '0';

  signal start_d     : std_logic := '0';
  signal start_pulse : std_logic := '0';
  signal run         : std_logic := '0';

  function calc_addr_rc(brow, bcol, r, c : integer) return integer is
  begin
    return (brow*B + r)*N + (bcol*B + c);
  end function;

  -- same packing as revision 4: element 0 in the most significant word
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
  valid      <= valid_reg;

  process(clk)
    variable tmpA, tmpB : block_array_t;
    variable ni, nj, np : integer;
    variable last_block : boolean;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= IDLE;
        valid_reg <= '0';
        i_blk <= 0; j_blk <= 0; p_blk <= 0;
        iss_k <= 0; iss_row <= 0; iss_col <= 0;
        v1 <= '0'; v2 <= '0'; idx1 <= 0; idx2 <= 0;
        addrA <= 0; addrB <= 0;
        outA_reg <= (others => '0');
        outB_reg <= (others => '0');
        start_d <= '0';
        start_pulse <= '0';
        run <= '0';
      else
        start_pulse <= start and (not start_d);
        start_d     <= start;
        if start_pulse = '1' then
          run <= '1';
        end if;

        case state is
          when IDLE =>
            valid_reg <= '0';
            v1 <= '0'; v2 <= '0';
            if start_pulse = '1' then
              i_blk <= 0; j_blk <= 0; p_blk <= 0;
              -- issue element 0 of block pair (0,0,0)
              addrA <= calc_addr_rc(0, 0, 0, 0);
              addrB <= calc_addr_rc(0, 0, 0, 0);
              v1 <= '1'; idx1 <= 0;
              iss_k <= 1; iss_row <= 0; iss_col <= 1;
              state <= FETCH;
            end if;

          when FETCH =>
            -- capture: data for the address set two edges ago is valid now
            if v2 = '1' then
              blockA(idx2) <= wordA64;
              blockB(idx2) <= wordB64;
              if idx2 = LAST_K then
                tmpA := blockA;  tmpB := blockB;
                tmpA(LAST_K) := wordA64;
                tmpB(LAST_K) := wordB64;
                outA_reg  <= pack_block(tmpA);
                outB_reg  <= pack_block(tmpB);
                valid_reg <= '1';
                state     <= OUTPUT;
              end if;
            end if;
            -- move the pipeline on
            v2 <= v1; idx2 <= idx1;
            -- issue the next address, one per cycle
            if iss_k <= LAST_K then
              addrA <= calc_addr_rc(i_blk, p_blk, iss_row, iss_col);
              addrB <= calc_addr_rc(p_blk, j_blk, iss_row, iss_col);
              v1 <= '1'; idx1 <= iss_k;
              iss_k <= iss_k + 1;
              if iss_col = B-1 then
                iss_col <= 0;
                if iss_row < B-1 then iss_row <= iss_row + 1; end if;
              else
                iss_col <= iss_col + 1;
              end if;
            else
              v1 <= '0';
            end if;

          when OUTPUT =>
            v1 <= '0'; v2 <= '0';
            if ready = '1' then
              valid_reg <= '0';
              last_block := (i_blk = NUM_BLOCKS-1) and
                            (j_blk = NUM_BLOCKS-1) and
                            (p_blk = NUM_BLOCKS-1);
              if last_block then
                run <= '0';
                state <= IDLE;
                i_blk <= 0; j_blk <= 0; p_blk <= 0;
                iss_k <= 0; iss_row <= 0; iss_col <= 0;
                addrA <= 0; addrB <= 0;
              else
                -- next block triple (p fastest, then j, then i)
                ni := i_blk; nj := j_blk; np := p_blk;
                if p_blk < (NUM_BLOCKS-1) then
                  np := p_blk + 1;
                else
                  np := 0;
                  if j_blk < (NUM_BLOCKS-1) then
                    nj := j_blk + 1;
                  else
                    nj := 0;
                    if i_blk < (NUM_BLOCKS-1) then ni := i_blk + 1; else ni := 0; end if;
                  end if;
                end if;
                i_blk <= ni; j_blk <= nj; p_blk <= np;
                if run = '1' then
                  -- issue element 0 of the next block pair right away
                  addrA <= calc_addr_rc(ni, np, 0, 0);
                  addrB <= calc_addr_rc(np, nj, 0, 0);
                  v1 <= '1'; idx1 <= 0;
                  iss_k <= 1; iss_row <= 0; iss_col <= 1;
                  state <= FETCH;
                else
                  state <= IDLE;
                end if;
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
