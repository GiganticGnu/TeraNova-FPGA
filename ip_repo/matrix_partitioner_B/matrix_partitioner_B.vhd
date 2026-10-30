-- =============================================================================
-- matrix_partitioner_B  --  variant v6 (ladder step 3_partitioner_v6, 30 Oct 2026)
--
-- On-chip copy of A and B with 10x reuse.
--
-- rev4/v5b fetch every block pair from the external BRAMs, element by element,
-- so every A and every B block is read 10 times (finding F5) at one element
-- per cycle (F4): 25-27 cycles per block pair.
--
-- v6 works in two phases after a start pulse:
--   LOAD    : copies A and B ONCE from the external BRAMs into 25 internal banks
--             per matrix (pipelined, one element of A and one of B per cycle,
--             2500 + 2 cycles). Element (r, c) goes to
--               bank = (r mod 5)*5 + (c mod 5)   (its position inside a block)
--               addr = (r / 5)*10 + (c / 5)      (the block it belongs to)
--   COMPUTE : for each block triple (i, j, p), p fastest, reads block A(i,p)
--             and block B(p,j) from all 25 banks in ONE cycle and offers them
--             on data_out_A/B with valid/ready, exactly as rev4 does.
-- The multiplier, not the memory, then sets the pace.
--
-- Same entity name, generics, ports, block order and output packing as rev4
-- (element 0 of a block in the most significant word): drop-in replacement.
-- Assumes BRAM port B read latency = 1 (checked in the block design .xci).
-- Internal memory: 2 x 25 banks of 100 x 64 bit (inferred RAM, LUTRAM or BRAM).
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
  constant NB     : integer := N / B;        -- blocks per row/column (10)
  constant NBANK  : integer := B * B;        -- banks per matrix (25)
  constant DEPTH  : integer := NB * NB;      -- blocks per matrix (100)
  constant LAST_E : integer := N * N - 1;    -- last element index (2499)

  type state_t is (IDLE, LOAD, RD, CAP, OUTPUT);
  signal state : state_t := IDLE;

  -- ---------------- load phase -----------------------------------------------
  -- issue side: element index, row, column of the next BRAM address
  signal ld_k   : integer range 0 to N*N := 0;
  signal ld_r   : integer range 0 to N-1 := 0;
  signal ld_c   : integer range 0 to N-1 := 0;
  -- 2-stage pipeline from "address set" to "data valid": valid, bank, address
  signal lv1, lv2 : std_logic := '0';
  signal lb1, lb2 : integer range 0 to NBANK-1 := 0;
  signal la1, la2 : integer range 0 to DEPTH-1 := 0;
  signal lastw1, lastw2 : std_logic := '0';

  signal addrA, addrB : integer range 0 to N*N-1 := 0;
  signal wordA64, wordB64 : std_logic_vector(63 downto 0);

  -- ---------------- internal banks ------------------------------------------
  type word_arr_t is array (0 to NBANK-1) of std_logic_vector(63 downto 0);
  signal rdA, rdB : word_arr_t;                     -- registered bank outputs
  signal we       : std_logic_vector(NBANK-1 downto 0);
  signal waddr    : integer range 0 to DEPTH-1 := 0;
  signal raddrA, raddrB : integer range 0 to DEPTH-1 := 0;

  -- ---------------- compute phase --------------------------------------------
  signal i_blk, j_blk, p_blk : integer range 0 to NB-1 := 0;

  signal outA_reg  : std_logic_vector((NBANK*WORD_WIDTH)-1 downto 0) := (others => '0');
  signal outB_reg  : std_logic_vector((NBANK*WORD_WIDTH)-1 downto 0) := (others => '0');
  signal valid_reg : std_logic := '0';

  signal start_d     : std_logic := '0';
  signal start_pulse : std_logic := '0';

  -- same packing as rev4: element 0 in the most significant word
  function pack_block(words : word_arr_t) return std_logic_vector is
    variable v : std_logic_vector((NBANK*WORD_WIDTH)-1 downto 0);
  begin
    for idx in 0 to NBANK-1 loop
      v((NBANK-1-idx)*WORD_WIDTH + WORD_WIDTH-1 downto (NBANK-1-idx)*WORD_WIDTH) := words(idx);
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

  -- one write enable per bank: the element that arrives now goes to bank lb2
  gen_we : for b in 0 to NBANK-1 generate
    we(b) <= '1' when (lv2 = '1' and lb2 = b) else '0';
  end generate;
  waddr <= la2;

  -- ---------------------------------------------------------------------------
  -- 25 banks per matrix: 1 write port (load), 1 registered read port (compute)
  -- ---------------------------------------------------------------------------
  gen_banks : for b in 0 to NBANK-1 generate
    type bank_t is array (0 to DEPTH-1) of std_logic_vector(63 downto 0);
    signal memA, memB : bank_t;
  begin
    process(clk)
    begin
      if rising_edge(clk) then
        if we(b) = '1' then
          memA(waddr) <= wordA64;
          memB(waddr) <= wordB64;
        end if;
        rdA(b) <= memA(raddrA);
        rdB(b) <= memB(raddrB);
      end if;
    end process;
  end generate;

  -- ---------------------------------------------------------------------------
  -- control
  -- ---------------------------------------------------------------------------
  process(clk)
    variable ni, nj, np : integer;
    variable last_block : boolean;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= IDLE;
        valid_reg <= '0';
        ld_k <= 0; ld_r <= 0; ld_c <= 0;
        lv1 <= '0'; lv2 <= '0'; lastw1 <= '0'; lastw2 <= '0';
        addrA <= 0; addrB <= 0;
        i_blk <= 0; j_blk <= 0; p_blk <= 0;
        raddrA <= 0; raddrB <= 0;
        start_d <= '0'; start_pulse <= '0';
      else
        start_pulse <= start and (not start_d);
        start_d     <= start;

        -- load pipeline moves on every cycle
        lv2 <= lv1; lb2 <= lb1; la2 <= la1; lastw2 <= lastw1;

        case state is
          when IDLE =>
            valid_reg <= '0';
            lv1 <= '0'; lastw1 <= '0';
            if start_pulse = '1' then
              ld_k <= 0; ld_r <= 0; ld_c <= 0;
              state <= LOAD;
            end if;

          when LOAD =>
            -- issue one BRAM address per cycle (same element of A and B)
            if ld_k <= LAST_E then
              addrA <= ld_k; addrB <= ld_k;
              lv1 <= '1';
              lb1 <= (ld_r mod B) * B + (ld_c mod B);
              la1 <= (ld_r / B) * NB + (ld_c / B);
              if ld_k = LAST_E then lastw1 <= '1'; else lastw1 <= '0'; end if;
              ld_k <= ld_k + 1;
              if ld_c = N-1 then
                ld_c <= 0;
                if ld_r < N-1 then ld_r <= ld_r + 1; end if;
              else
                ld_c <= ld_c + 1;
              end if;
            else
              lv1 <= '0'; lastw1 <= '0';
            end if;
            -- the last element is written at this edge: start computing
            if lv2 = '1' and lastw2 = '1' then
              i_blk <= 0; j_blk <= 0; p_blk <= 0;
              state <= RD;
            end if;

          when RD =>
            -- read A(i,p) and B(p,j): all 25 elements in one cycle
            lv1 <= '0'; lastw1 <= '0';
            raddrA <= i_blk * NB + p_blk;
            raddrB <= p_blk * NB + j_blk;
            state <= CAP;

          when CAP =>
            -- the bank outputs are registered: wait one edge for them
            state <= OUTPUT;

          when OUTPUT =>
            if valid_reg = '0' then
              outA_reg  <= pack_block(rdA);
              outB_reg  <= pack_block(rdB);
              valid_reg <= '1';
            elsif ready = '1' then
              valid_reg <= '0';
              last_block := (i_blk = NB-1) and (j_blk = NB-1) and (p_blk = NB-1);
              if last_block then
                state <= IDLE;
              else
                ni := i_blk; nj := j_blk; np := p_blk;
                if p_blk < NB-1 then
                  np := p_blk + 1;
                else
                  np := 0;
                  if j_blk < NB-1 then
                    nj := j_blk + 1;
                  else
                    nj := 0;
                    if i_blk < NB-1 then ni := i_blk + 1; else ni := 0; end if;
                  end if;
                end if;
                i_blk <= ni; j_blk <= nj; p_blk <= np;
                state <= RD;
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
