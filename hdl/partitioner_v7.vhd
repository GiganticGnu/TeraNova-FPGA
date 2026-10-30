-- =============================================================================
-- partitioner_v7  --  HARDWARE COPY of sim/variants/matrix_partitioner_B_v7.vhd
-- (ladder step 4_burst_datapath). Used in the block design as an RTL module
-- reference by scripts/6_burst_datapath.tcl.
-- Differences with the simulated file, nothing else (check: fc /n or git diff):
--   * entity name partitioner_v7 (the old packaged IP matrix_partitioner_B
--     keeps its own name, so the two can never be mixed up)
--   * X_INTERFACE attributes, so Vivado sees m_axi_rd_* as ONE AXI4 read-only
--     master (128 bit, 64-bit address, bursts up to 256, 8 reads in flight),
--     clocked by clk and reset by rst (active high)
-- =============================================================================
-- matrix_partitioner_B  --  variant v7 (ladder step 4_burst_datapath, 30 Oct 2026)
--
-- Burst data path: A and B are read from PS DDR by this block itself, through
-- an AXI4 read master (for an S_AXI_HP port of the Zynq UltraScale+ PS),
-- instead of being written into BRAMs by the CPU one value at a time
-- (finding F1). Everything after loading is identical to v6.
--
--   LOAD    : reads A (2500 x 64 bit) from a_base and then B from b_base in
--             INCR bursts of 128-bit beats (2 elements per beat), at most 256
--             beats per burst and never across a 4 KB boundary, with up to
--             MAX_OUT reads in flight. The two elements of a beat are
--             neighbours in a row, so they always go to two DIFFERENT banks
--             and are written in the same cycle:
--               bank = (r mod 5)*5 + (c mod 5), addr = (r / 5)*10 + (c / 5)
--   COMPUTE : as v6: block A(i,p) and B(p,j) from all 25 banks in one cycle,
--             offered on data_out_A/B with valid/ready, p fastest.
--
-- Interface change compared with rev4..v6: the four BRAM ports are replaced by
-- the AXI4 read master m_axi_rd_* and the byte addresses a_base / b_base
-- (16-byte aligned; 4 KB aligned gives the fewest bursts). data_out_A/B,
-- valid/ready, start, clk and rst are unchanged.
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity partitioner_v7 is
  generic (
    N          : integer := 50;
    B          : integer := 5;
    WORD_WIDTH : integer := 64;
    MAX_OUT    : integer := 8     -- read bursts in flight
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;  -- sync active-high
    start : in  std_logic;  -- can be a 1-cycle pulse

    a_base : in std_logic_vector(63 downto 0);   -- byte address of A in PS DDR
    b_base : in std_logic_vector(63 downto 0);   -- byte address of B in PS DDR

    -- AXI4 read master (128-bit), single ID
    m_axi_rd_ARVALID : out std_logic;
    m_axi_rd_ARREADY : in  std_logic;
    m_axi_rd_ARADDR  : out std_logic_vector(63 downto 0);
    m_axi_rd_ARLEN   : out std_logic_vector(7 downto 0);
    m_axi_rd_ARSIZE  : out std_logic_vector(2 downto 0);
    m_axi_rd_ARBURST : out std_logic_vector(1 downto 0);
    m_axi_rd_ARCACHE : out std_logic_vector(3 downto 0);
    m_axi_rd_ARPROT  : out std_logic_vector(2 downto 0);
    m_axi_rd_RVALID  : in  std_logic;
    m_axi_rd_RREADY  : out std_logic;
    m_axi_rd_RDATA   : in  std_logic_vector(127 downto 0);
    m_axi_rd_RLAST   : in  std_logic;
    m_axi_rd_RRESP   : in  std_logic_vector(1 downto 0);

    data_out_A : out std_logic_vector((B*B*WORD_WIDTH)-1 downto 0);
    data_out_B : out std_logic_vector((B*B*WORD_WIDTH)-1 downto 0);

    valid : out std_logic;
    ready : in  std_logic
  );

  -- ---------------- interface attributes for the Vivado block design --------
  attribute X_INTERFACE_INFO      : string;
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_INFO      of clk : signal is "xilinx.com:signal:clock:1.0 clk CLK";
  attribute X_INTERFACE_PARAMETER of clk : signal is "ASSOCIATED_BUSIF m_axi_rd, ASSOCIATED_RESET rst";
  attribute X_INTERFACE_INFO      of rst : signal is "xilinx.com:signal:reset:1.0 rst RST";
  attribute X_INTERFACE_PARAMETER of rst : signal is "POLARITY ACTIVE_HIGH";
  attribute X_INTERFACE_INFO of m_axi_rd_ARVALID : signal is "xilinx.com:interface:aximm:1.0 m_axi_rd ARVALID";
  attribute X_INTERFACE_INFO of m_axi_rd_ARREADY : signal is "xilinx.com:interface:aximm:1.0 m_axi_rd ARREADY";
  attribute X_INTERFACE_INFO of m_axi_rd_ARADDR : signal is "xilinx.com:interface:aximm:1.0 m_axi_rd ARADDR";
  attribute X_INTERFACE_INFO of m_axi_rd_ARLEN : signal is "xilinx.com:interface:aximm:1.0 m_axi_rd ARLEN";
  attribute X_INTERFACE_INFO of m_axi_rd_ARSIZE : signal is "xilinx.com:interface:aximm:1.0 m_axi_rd ARSIZE";
  attribute X_INTERFACE_INFO of m_axi_rd_ARBURST : signal is "xilinx.com:interface:aximm:1.0 m_axi_rd ARBURST";
  attribute X_INTERFACE_INFO of m_axi_rd_ARCACHE : signal is "xilinx.com:interface:aximm:1.0 m_axi_rd ARCACHE";
  attribute X_INTERFACE_INFO of m_axi_rd_ARPROT : signal is "xilinx.com:interface:aximm:1.0 m_axi_rd ARPROT";
  attribute X_INTERFACE_INFO of m_axi_rd_RVALID : signal is "xilinx.com:interface:aximm:1.0 m_axi_rd RVALID";
  attribute X_INTERFACE_INFO of m_axi_rd_RREADY : signal is "xilinx.com:interface:aximm:1.0 m_axi_rd RREADY";
  attribute X_INTERFACE_INFO of m_axi_rd_RDATA : signal is "xilinx.com:interface:aximm:1.0 m_axi_rd RDATA";
  attribute X_INTERFACE_INFO of m_axi_rd_RLAST : signal is "xilinx.com:interface:aximm:1.0 m_axi_rd RLAST";
  attribute X_INTERFACE_INFO of m_axi_rd_RRESP : signal is "xilinx.com:interface:aximm:1.0 m_axi_rd RRESP";
  attribute X_INTERFACE_PARAMETER of m_axi_rd_ARVALID : signal is "XIL_INTERFACENAME m_axi_rd, PROTOCOL AXI4, READ_WRITE_MODE READ_ONLY, DATA_WIDTH 128, ADDR_WIDTH 64, ID_WIDTH 0, MAX_BURST_LENGTH 256, NUM_READ_OUTSTANDING 8, NUM_WRITE_OUTSTANDING 0, SUPPORTS_NARROW_BURST 0, HAS_BURST 1, HAS_LOCK 0, HAS_CACHE 1, HAS_PROT 1, HAS_QOS 0, HAS_REGION 0, HAS_RRESP 1, HAS_BRESP 0, HAS_WSTRB 0";
end entity;

architecture rtl of partitioner_v7 is


  constant NB     : integer := N / B;        -- 10
  constant NBANK  : integer := B * B;        -- 25
  constant DEPTH  : integer := NB * NB;      -- 100
  constant BEATS  : integer := N * N / 2;    -- 1250 beats per matrix
  constant TOTAL  : integer := 2 * BEATS;    -- 2500 beats for A and B

  type state_t is (IDLE, LOAD, RD, CAP, OUTPUT);
  signal state : state_t := IDLE;

  -- ---------------- AR (address) side ----------------------------------------
  signal ar_valid  : std_logic := '0';
  signal ar_addr   : unsigned(63 downto 0) := (others => '0');
  signal ar_len    : integer range 0 to 255 := 0;
  signal iss_mat   : integer range 0 to 2 := 0;          -- 0 = A, 1 = B, 2 = done
  signal iss_beat  : integer range 0 to BEATS := 0;      -- beats already requested of this matrix
  signal in_flight : integer range 0 to MAX_OUT := 0;

  -- ---------------- R (data) side --------------------------------------------
  signal rcv       : integer range 0 to TOTAL := 0;      -- beats received
  signal rcv_r     : integer range 0 to N-1 := 0;        -- row of the first element of the next beat
  signal rcv_c     : integer range 0 to N-2 := 0;        -- its column (even)
  -- registered write of one beat (two elements)
  signal w_valid   : std_logic := '0';
  signal w_isB     : std_logic := '0';
  signal w_last    : std_logic := '0';
  signal w_bank0, w_bank1 : integer range 0 to NBANK-1 := 0;
  signal w_addr0, w_addr1 : integer range 0 to DEPTH-1 := 0;
  signal w_data0, w_data1 : std_logic_vector(63 downto 0) := (others => '0');

  -- ---------------- internal banks ------------------------------------------
  type word_arr_t is array (0 to NBANK-1) of std_logic_vector(63 downto 0);
  signal rdA, rdB : word_arr_t;
  signal raddrA, raddrB : integer range 0 to DEPTH-1 := 0;

  -- ---------------- compute ---------------------------------------------------
  signal i_blk, j_blk, p_blk : integer range 0 to NB-1 := 0;
  signal outA_reg  : std_logic_vector((NBANK*WORD_WIDTH)-1 downto 0) := (others => '0');
  signal outB_reg  : std_logic_vector((NBANK*WORD_WIDTH)-1 downto 0) := (others => '0');
  signal valid_reg : std_logic := '0';

  signal start_d, start_pulse : std_logic := '0';
  signal rready_i : std_logic;

  function pack_block(words : word_arr_t) return std_logic_vector is
    variable v : std_logic_vector((NBANK*WORD_WIDTH)-1 downto 0);
  begin
    for idx in 0 to NBANK-1 loop
      v((NBANK-1-idx)*WORD_WIDTH + WORD_WIDTH-1 downto (NBANK-1-idx)*WORD_WIDTH) := words(idx);
    end loop;
    return v;
  end function;

  -- beats from addr to the next 4 KB boundary (16-byte beats)
  function to_4k(a : unsigned(63 downto 0)) return integer is
  begin
    return (4096 - to_integer(a(11 downto 0))) / 16;
  end function;

begin
  m_axi_rd_ARVALID <= ar_valid;
  m_axi_rd_ARADDR  <= std_logic_vector(ar_addr);
  m_axi_rd_ARLEN   <= std_logic_vector(to_unsigned(ar_len, 8));
  m_axi_rd_ARSIZE  <= "100";        -- 16 bytes per beat
  m_axi_rd_ARBURST <= "01";         -- INCR
  m_axi_rd_ARCACHE <= "0011";       -- normal, non-cacheable, bufferable
  m_axi_rd_ARPROT  <= "000";
  rready_i <= '1' when state = LOAD else '0';
  m_axi_rd_RREADY  <= rready_i;

  data_out_A <= outA_reg;
  data_out_B <= outB_reg;
  valid      <= valid_reg;

  -- ---------------------------------------------------------------------------
  -- 25 banks per matrix: 1 write port (load), 1 registered read port (compute).
  -- A beat writes two different banks, each with its own address.
  -- ---------------------------------------------------------------------------
  gen_banks : for k in 0 to NBANK-1 generate
    type bank_t is array (0 to DEPTH-1) of std_logic_vector(63 downto 0);
    signal memA, memB : bank_t;
  begin
    process(clk)
      variable we : boolean;
      variable wa : integer range 0 to DEPTH-1;
      variable wd : std_logic_vector(63 downto 0);
    begin
      if rising_edge(clk) then
        we := false; wa := 0; wd := (others => '0');
        if w_valid = '1' and w_bank0 = k then we := true; wa := w_addr0; wd := w_data0; end if;
        if w_valid = '1' and w_bank1 = k then we := true; wa := w_addr1; wd := w_data1; end if;
        if we and w_isB = '0' then memA(wa) <= wd; end if;
        if we and w_isB = '1' then memB(wa) <= wd; end if;
        rdA(k) <= memA(raddrA);
        rdB(k) <= memB(raddrB);
      end if;
    end process;
  end generate;

  -- ---------------------------------------------------------------------------
  -- control
  -- ---------------------------------------------------------------------------
  process(clk)
    variable ni, nj, np : integer;
    variable last_block : boolean;
    variable ar_hs, r_hs : boolean;
    variable left, len : integer;
    variable base : unsigned(63 downto 0);
    variable c1 : integer;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= IDLE; valid_reg <= '0';
        ar_valid <= '0'; iss_mat <= 2; iss_beat <= 0; in_flight <= 0;
        rcv <= 0; rcv_r <= 0; rcv_c <= 0; w_valid <= '0'; w_last <= '0';
        i_blk <= 0; j_blk <= 0; p_blk <= 0;
        start_d <= '0'; start_pulse <= '0';
      else
        start_pulse <= start and (not start_d);
        start_d     <= start;
        w_valid <= '0'; w_last <= '0';

        ar_hs := (ar_valid = '1' and m_axi_rd_ARREADY = '1');
        r_hs  := (m_axi_rd_RVALID = '1' and rready_i = '1');

        case state is
          when IDLE =>
            valid_reg <= '0';
            if start_pulse = '1' then
              iss_mat <= 0; iss_beat <= 0; in_flight <= 0; ar_valid <= '0';
              rcv <= 0; rcv_r <= 0; rcv_c <= 0;
              state <= LOAD;
            end if;

          when LOAD =>
            -- ---- address side: next burst when the previous one is accepted
            if ar_hs then ar_valid <= '0'; end if;
            -- in-flight count: +1 per accepted address, -1 per last beat received
            if ar_hs and not (r_hs and m_axi_rd_RLAST = '1') then
              in_flight <= in_flight + 1;
            elsif r_hs and m_axi_rd_RLAST = '1' and not ar_hs then
              in_flight <= in_flight - 1;
            end if;
            if (ar_valid = '0' or ar_hs) and iss_mat < 2 and
               (in_flight + boolean'pos(ar_hs) < MAX_OUT) then
              if iss_mat = 0 then base := unsigned(a_base); else base := unsigned(b_base); end if;
              base := base + to_unsigned(iss_beat * 16, 64);
              left := BEATS - iss_beat;
              len  := left;
              if len > 256 then len := 256; end if;
              if len > to_4k(base) then len := to_4k(base); end if;
              ar_valid <= '1'; ar_addr <= base; ar_len <= len - 1;
              if iss_beat + len = BEATS then
                iss_beat <= 0; iss_mat <= iss_mat + 1;
              else
                iss_beat <= iss_beat + len;
              end if;
            end if;

            -- ---- data side: two elements per beat into two banks
            if r_hs then
              c1 := rcv_c + 1;
              w_valid <= '1';
              if rcv < BEATS then w_isB <= '0'; else w_isB <= '1'; end if;
              w_bank0 <= (rcv_r mod B) * B + (rcv_c mod B);
              w_bank1 <= (rcv_r mod B) * B + (c1 mod B);
              w_addr0 <= (rcv_r / B) * NB + (rcv_c / B);
              w_addr1 <= (rcv_r / B) * NB + (c1 / B);
              w_data0 <= m_axi_rd_RDATA(63 downto 0);
              w_data1 <= m_axi_rd_RDATA(127 downto 64);
              if rcv = TOTAL - 1 then w_last <= '1'; end if;
              rcv <= rcv + 1;
              if rcv_c = N - 2 then
                rcv_c <= 0;
                if rcv_r = N - 1 then rcv_r <= 0; else rcv_r <= rcv_r + 1; end if;
              else
                rcv_c <= rcv_c + 2;
              end if;
            end if;

            -- ---- the last beat is written at this edge: start computing
            if w_valid = '1' and w_last = '1' then
              i_blk <= 0; j_blk <= 0; p_blk <= 0;
              state <= RD;
            end if;

          when RD =>
            raddrA <= i_blk * NB + p_blk;
            raddrB <= p_blk * NB + j_blk;
            state <= CAP;

          when CAP =>
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
