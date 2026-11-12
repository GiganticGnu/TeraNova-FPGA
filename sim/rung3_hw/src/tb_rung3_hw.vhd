-- =============================================================================
-- tb_rung3_hw  --  rung 3 (branch partitioner-v6) as it is built on the board
-- TeraNova FPGA project, Kai Janssen, Nov 2026.
--
-- Purpose
--   1. Correctness: follow the data through EVERY stage and report the first
--      stage where it differs from the golden model (BRAM -> partitioner ->
--      multiplier -> accumulator -> AXI address -> AXI data -> C in DDR4).
--   2. Timing: time-stamp every stage of one run (CPU BRAM load, start,
--      on-chip copy, multiply/accumulate, write-back, done, interrupt,
--      CPU read-back) so it shows which part takes longest.
--
-- What is the SAME as the board (taken from the partitioner-v6 branch):
--   * the RTL of every block, as packaged in ip_repo (partitioner v6,
--     MatMul5x5_PAR_IF, MatMul5x5_Accumulator NUM_ACCUMULATIONS=10,
--     matrix_to_ports, toggle2pulse pulse_width=105, RAM_INTERFACE writer fix)
--   * the block-design wiring of accu_to_DDR.bd: mult_gen x4 on both BRAM
--     addresses, Part0/Part1 = A high/low, Part3/Part2 = B high/low,
--     ilconcat (C0 = LSB), DDR_BASEADDRESS = 0x4_0000_0000 into RAM_INTERFACE,
--     done -> GPIO2 + pl_ps_irq0, start = GPIO toggle -> toggle2pulse
--   * the BRAM settings of the .xci files (8192 x 32, read latency 1)
--   * the application flow (helloworld.c, rung 3): per run load BRAMs,
--     clear C, toggle start, wait for the done interrupt, read C back
-- What is a MODEL: the PS side (CPU access times, interrupt latency) and the
-- SmartConnect + DDR4 (fixed write-response latency LAT). The CPU times are
-- generics; put in the measured probe values of the board log (CSV,probe).
--
-- Generics for what-if experiments (default = the real design):
--   DDR_BASE_HI     DDR input of RAM_INTERFACE = DDR_BASE_HI * 2^32 (4 = real)
--   BRAM_LAT        BRAM port-B read latency (1 = as configured)
--   CPU_LOADS_BRAM  0 = start with empty BRAMs
--   FILL_POISON     1 = C is filled with 0xDEADBEEFDEADBEEF before a run, so
--                   "never written" and "written as 0" look different
--                   (0 = fill with 0, exactly like the application)
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.hw_pkg.all;

entity tb_rung3_hw is
  generic (
    N_RUNS         : integer := 2;
    LAT            : integer := 40;      -- DDR4 write response latency (cycles)
    DDR_BASE_HI    : integer := 4;       -- DDR input = DDR_BASE_HI * 2^32 (4 = 0x4_0000_0000)
    BRAM_LAT       : integer := 1;
    CPU_LOADS_BRAM : integer := 1;       -- 0 = BRAMs stay empty (what-if)
    FILL_POISON    : integer := 1;       -- 1 = C := 0xDEADBEEF.. before a run, 0 = C := 0 (as the app)
    -- PS-side model (ns). Estimates until replaced by measured CSV,probe values.
    T_BRAM_WR_NS   : integer := 150;     -- one 32-bit PS -> BRAM write
    T_DDR_RD_NS    : integer := 300;     -- one 64-bit PL-DDR4 -> PS read
    T_GPIO_NS      : integer := 150;     -- GPIO write PS -> PL
    T_IRQ_NS       : integer := 1000);   -- done edge -> ISR time stamp
end entity;

architecture sim of tb_rung3_hw is
  constant TCLK : time := 10 ns;                       -- 100 MHz
  -- expected C: filled at time 0 by a process (as a constant, XSim would
  -- try to compute it during static elaboration, which takes very long)
  signal CG     : u64_arr(0 to N*N-1) := (others => (others => '0'));
  constant DDR_BASE : std_logic_vector(63 downto 0) :=
    std_logic_vector(shift_left(to_unsigned(DDR_BASE_HI, 64), 32));
  function fillv return std_logic_vector is
  begin
    if FILL_POISON = 1 then return POISON; else return x"0000000000000000"; end if;
  end function;
  constant FILL_VAL : std_logic_vector(63 downto 0) := fillv;

  -- which stage the system is in (shown as text in the wave window)
  type stage_t is (RESET, CPU_LOAD_BRAM, CPU_CLEAR_C, START_GPIO, PL_ONCHIP_COPY,
                   PL_MULT_ACC, PL_DRAIN_WRITES, IRQ_LATENCY, CPU_READ_C, CPU_CHECK);
  signal cpu_stage, pl_stage, stage : stage_t := RESET;
  -- run-1 stage boundaries (ns) for the wave markers
  -- 64-bit values for the wave window (BRAM high & low half joined)
  signal bram_A_value, bram_B_value : std_logic_vector(63 downto 0);
  signal mk_load0, mk_gpio, mk_pulse, mk_pair0, mk_pairN, mk_done, mk_isr, mk_rb0, mk_rb1 : integer := 0;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';                       -- peripheral_reset
  signal rst_n : std_logic;                            -- peripheral_aresetn
  signal sim_end : boolean := false;

  -- BRAMs: Part0 = A high, Part1 = A low, Part3 = B high, Part2 = B low
  type sl4  is array (0 to 3) of std_logic;
  type v32x4 is array (0 to 3) of std_logic_vector(31 downto 0);
  signal wea  : sl4 := (others => '0');
  signal addra : integer range 0 to 8191 := 0;
  signal dina : std_logic_vector(31 downto 0) := (others => '0');
  signal doutb : v32x4;
  signal addrA12, addrB12 : std_logic_vector(11 downto 0);
  signal addrb_A, addrb_B : std_logic_vector(31 downto 0);

  -- start / done
  signal gpio_start, pulse : std_logic := '0';
  signal done : std_logic := '0';
  signal done_v : std_logic_vector(0 downto 0);

  -- data path
  signal outA, outB : std_logic_vector(1599 downto 0);
  signal p_valid, p_ready, m_valid, m_ready, c_valid, c_ready : std_logic;
  type v64_arr is array (0 to 24) of std_logic_vector(63 downto 0);
  signal A, Bm, M, C : v64_arr;
  signal dout : std_logic_vector(1599 downto 0);

  -- AXI
  signal awvalid, awready, wvalid, wready, wlast, bvalid, bready, arvalid : std_logic;
  signal awaddr : std_logic_vector(63 downto 0);
  signal awlen  : std_logic_vector(7 downto 0);
  signal awsize : std_logic_vector(2 downto 0);
  signal awburst : std_logic_vector(1 downto 0);
  signal wdata  : std_logic_vector(63 downto 0);
  signal wstrb  : std_logic_vector(7 downto 0);
  signal bresp  : std_logic_vector(1 downto 0);
  signal fill   : std_logic := '0';
  signal rd_addr : integer range 0 to 4095 := 0;
  signal rd_data : std_logic_vector(63 downto 0);
  signal n_bursts, n_beats, n_decerr, n_outside_c, n_proto_err : integer;
  signal first_bad_addr : std_logic_vector(63 downto 0);

  -- ---------------- monitors (cumulative over all runs) --------------------
  signal pairs, muls, blks, aws, beats, nresp : integer := 0;     -- handshakes
  signal err_bram, err_part, err_mul, err_acc, err_awaddr, err_wdata, err_bresp : integer := 0;
  signal irq_count : integer := 0;
  signal t_isr  : integer := 0;
  -- per-run stage time stamps (ns), written by the monitors
  signal t_pulse, t_lastaddr, t_pair0, t_pairN, t_mul0, t_mulN, t_blk0, t_blkN,
         t_aw0, t_bN, t_done : integer := 0;
  signal cyc_mult_busy, cyc_acc_wait, cyc_writer_stall, cyc_axi_busy, cyc_run : integer := 0;
  signal in_run : std_logic := '0';
  signal outstanding : integer := 0;

  procedure say(s : string) is
    variable l : line;
  begin
    write(l, s); writeline(output, l);
  end procedure;

  impure function ns_now return integer is
  begin
    return now / 1 ns;
  end function;

  function pad(s : string; w : integer) return string is
    variable r : string(1 to w) := (others => ' ');
  begin
    if s'length >= w then return s; end if;
    r(1 to s'length) := s; return r;
  end function;
  function lpad(s : string; w : integer) return string is
    variable r : string(1 to w) := (others => ' ');
  begin
    if s'length >= w then return s; end if;
    r(w - s'length + 1 to w) := s; return r;
  end function;
begin
  clk <= not clk after TCLK / 2 when not sim_end;

  golden : process
    variable v : u64_arr(0 to N*N-1);
    variable acc : integer;
  begin
    -- integer arithmetic is enough for this data set (max 158 393 725)
    for i in 0 to N-1 loop
      for j in 0 to N-1 loop
        acc := 0;
        for k in 0 to N-1 loop
          acc := acc + (i*N + k + A_OFF) * (k*N + j + B_OFF);
        end loop;
        v(i*N + j) := to_unsigned(acc, 64);
      end loop;
    end loop;
    CG <= v;
    wait;
  end process;
  rst_n <= not rst;

  -- ===================== hardware (block design) =============================
  part0 : entity work.bram_tdp_model generic map (BRAM_LAT)
    port map (clk, wea(0), addra, dina, '1', rst, addrb_A, doutb(0));   -- A high
  part1 : entity work.bram_tdp_model generic map (BRAM_LAT)
    port map (clk, wea(1), addra, dina, '1', rst, addrb_A, doutb(1));   -- A low
  part3 : entity work.bram_tdp_model generic map (BRAM_LAT)
    port map (clk, wea(3), addra, dina, '1', rst, addrb_B, doutb(3));   -- B high
  part2 : entity work.bram_tdp_model generic map (BRAM_LAT)
    port map (clk, wea(2), addra, dina, '1', rst, addrb_B, doutb(2));   -- B low

  bram_A_value <= doutb(0) & doutb(1);
  bram_B_value <= doutb(3) & doutb(2);

  -- mult_gen_1 / mult_gen_0: constant x4, 21-bit P, latency 0 (PipeStages = 0)
  addrb_A <= std_logic_vector(resize(unsigned(addrA12) * 4, 32));
  addrb_B <= std_logic_vector(resize(unsigned(addrB12) * 4, 32));

  t2p : entity work.toggle2pulse generic map (pulse_width => 105)
    port map (toggle => gpio_start, pulse => pulse, clk => clk, rst => rst);

  part : entity work.matrix_partitioner_B
    port map (clk => clk, rst => rst, start => pulse,
              bram_addr_A => addrA12, bram_addr_B => addrB12,
              data_in_highA => doutb(0), data_in_lowA => doutb(1),
              data_in_highB => doutb(3), data_in_lowB => doutb(2),
              data_out_A => outA, data_out_B => outB,
              valid => p_valid, ready => p_ready);

  m2pA : entity work.matrix_to_ports port map (M_in => outA,
    Out0=>A(0),Out1=>A(1),Out2=>A(2),Out3=>A(3),Out4=>A(4),Out5=>A(5),Out6=>A(6),Out7=>A(7),Out8=>A(8),Out9=>A(9),
    Out10=>A(10),Out11=>A(11),Out12=>A(12),Out13=>A(13),Out14=>A(14),Out15=>A(15),Out16=>A(16),Out17=>A(17),Out18=>A(18),Out19=>A(19),
    Out20=>A(20),Out21=>A(21),Out22=>A(22),Out23=>A(23),Out24=>A(24));
  m2pB : entity work.matrix_to_ports port map (M_in => outB,
    Out0=>Bm(0),Out1=>Bm(1),Out2=>Bm(2),Out3=>Bm(3),Out4=>Bm(4),Out5=>Bm(5),Out6=>Bm(6),Out7=>Bm(7),Out8=>Bm(8),Out9=>Bm(9),
    Out10=>Bm(10),Out11=>Bm(11),Out12=>Bm(12),Out13=>Bm(13),Out14=>Bm(14),Out15=>Bm(15),Out16=>Bm(16),Out17=>Bm(17),Out18=>Bm(18),Out19=>Bm(19),
    Out20=>Bm(20),Out21=>Bm(21),Out22=>Bm(22),Out23=>Bm(23),Out24=>Bm(24));

  mm : entity work.MatMul5x5_PAR_IF port map (clk => clk, rst => rst,
    A0=>A(0),A1=>A(1),A2=>A(2),A3=>A(3),A4=>A(4),A5=>A(5),A6=>A(6),A7=>A(7),A8=>A(8),A9=>A(9),
    A10=>A(10),A11=>A(11),A12=>A(12),A13=>A(13),A14=>A(14),A15=>A(15),A16=>A(16),A17=>A(17),A18=>A(18),A19=>A(19),
    A20=>A(20),A21=>A(21),A22=>A(22),A23=>A(23),A24=>A(24),
    B0=>Bm(0),B1=>Bm(1),B2=>Bm(2),B3=>Bm(3),B4=>Bm(4),B5=>Bm(5),B6=>Bm(6),B7=>Bm(7),B8=>Bm(8),B9=>Bm(9),
    B10=>Bm(10),B11=>Bm(11),B12=>Bm(12),B13=>Bm(13),B14=>Bm(14),B15=>Bm(15),B16=>Bm(16),B17=>Bm(17),B18=>Bm(18),B19=>Bm(19),
    B20=>Bm(20),B21=>Bm(21),B22=>Bm(22),B23=>Bm(23),B24=>Bm(24),
    valid => p_valid, ready => p_ready,
    C0=>M(0),C1=>M(1),C2=>M(2),C3=>M(3),C4=>M(4),C5=>M(5),C6=>M(6),C7=>M(7),C8=>M(8),C9=>M(9),
    C10=>M(10),C11=>M(11),C12=>M(12),C13=>M(13),C14=>M(14),C15=>M(15),C16=>M(16),C17=>M(17),C18=>M(18),C19=>M(19),
    C20=>M(20),C21=>M(21),C22=>M(22),C23=>M(23),C24=>M(24),
    C_valid => m_valid, C_ready => m_ready);

  acc : entity work.MatMul5x5_Accumulator generic map (NUM_ACCUMULATIONS => 10)
    port map (clk => clk, rst => rst,
    A0=>M(0),A1=>M(1),A2=>M(2),A3=>M(3),A4=>M(4),A5=>M(5),A6=>M(6),A7=>M(7),A8=>M(8),A9=>M(9),
    A10=>M(10),A11=>M(11),A12=>M(12),A13=>M(13),A14=>M(14),A15=>M(15),A16=>M(16),A17=>M(17),A18=>M(18),A19=>M(19),
    A20=>M(20),A21=>M(21),A22=>M(22),A23=>M(23),A24=>M(24),
    valid => m_valid, ready => m_ready,
    C0=>C(0),C1=>C(1),C2=>C(2),C3=>C(3),C4=>C(4),C5=>C(5),C6=>C(6),C7=>C(7),C8=>C(8),C9=>C(9),
    C10=>C(10),C11=>C(11),C12=>C(12),C13=>C(13),C14=>C(14),C15=>C(15),C16=>C(16),C17=>C(17),C18=>C(18),C19=>C(19),
    C20=>C(20),C21=>C(21),C22=>C(22),C23=>C(23),C24=>C(24),
    C_valid => c_valid, C_ready => c_ready);

  -- ilconcat_0: In0 = least significant 64 bits
  gen_cat : for e in 0 to 24 generate
    dout(64*e+63 downto 64*e) <= C(e);
  end generate;

  ri : entity work.RAM_INTERFACE
    port map (ap_clk => clk, ap_rst_n => rst_n,
      m_axi_gmem_AWVALID => awvalid, m_axi_gmem_AWREADY => awready, m_axi_gmem_AWADDR => awaddr,
      m_axi_gmem_AWID => open, m_axi_gmem_AWLEN => awlen, m_axi_gmem_AWSIZE => awsize, m_axi_gmem_AWBURST => awburst,
      m_axi_gmem_AWLOCK => open, m_axi_gmem_AWCACHE => open, m_axi_gmem_AWPROT => open, m_axi_gmem_AWQOS => open,
      m_axi_gmem_AWREGION => open, m_axi_gmem_AWUSER => open,
      m_axi_gmem_WVALID => wvalid, m_axi_gmem_WREADY => wready, m_axi_gmem_WDATA => wdata,
      m_axi_gmem_WSTRB => wstrb, m_axi_gmem_WLAST => wlast, m_axi_gmem_WID => open, m_axi_gmem_WUSER => open,
      m_axi_gmem_ARVALID => arvalid, m_axi_gmem_ARREADY => '1', m_axi_gmem_ARADDR => open,
      m_axi_gmem_ARID => open, m_axi_gmem_ARLEN => open, m_axi_gmem_ARSIZE => open, m_axi_gmem_ARBURST => open,
      m_axi_gmem_ARLOCK => open, m_axi_gmem_ARCACHE => open, m_axi_gmem_ARPROT => open, m_axi_gmem_ARQOS => open,
      m_axi_gmem_ARREGION => open, m_axi_gmem_ARUSER => open,
      m_axi_gmem_RVALID => '0', m_axi_gmem_RREADY => open, m_axi_gmem_RDATA => (others => '0'),
      m_axi_gmem_RLAST => '0', m_axi_gmem_RID => "0", m_axi_gmem_RUSER => "0", m_axi_gmem_RRESP => "00",
      m_axi_gmem_BVALID => bvalid, m_axi_gmem_BREADY => bready, m_axi_gmem_BRESP => bresp,
      m_axi_gmem_BID => "0", m_axi_gmem_BUSER => "0",
      DDR => DDR_BASE,
      data_dout => dout, data_empty_n => c_valid, data_read => c_ready,
      done => done_v);
  done <= done_v(0);

  ddr : entity work.axi_ddr_model generic map (B_LATENCY => LAT)
    port map (clk => clk, rst => rst,
      awvalid => awvalid, awready => awready, awaddr => awaddr, awlen => awlen,
      awsize => awsize, awburst => awburst,
      wvalid => wvalid, wready => wready, wdata => wdata, wstrb => wstrb, wlast => wlast,
      bvalid => bvalid, bready => bready, bresp => bresp,
      fill => fill, fill_val => FILL_VAL, rd_addr => rd_addr, rd_data => rd_data,
      n_bursts => n_bursts, n_beats => n_beats, n_decerr => n_decerr,
      n_outside_c => n_outside_c, n_proto_err => n_proto_err, first_bad_addr => first_bad_addr);

  -- ===================== stage monitors / golden checkers ====================
  process(clk)
    variable np, nm, nk, na, nw, nb : integer := 0;
    variable i, j, p, e, bi, r, word : integer;
    variable got, exp : u64;
    variable eb, ep, em, ec, ea, ew, er : integer := 0;
    variable prev_addr : integer := -1;
    variable loading : boolean := false;
    variable pulse_d, done_d : std_logic := '0';
    variable outst : integer := 0;
    variable row_left : integer := 5;
    variable nrow : integer := 0;
  begin
    if rising_edge(clk) then
      -- --- start pulse seen by the partitioner (rising edge of 'pulse')
      if pulse = '1' and pulse_d = '0' then
        t_pulse <= ns_now; loading := true; prev_addr := -1;
        pl_stage <= PL_ONCHIP_COPY;
      end if;
      pulse_d := pulse;

      -- --- 1. BRAM -> partitioner: data for the address of the previous
      --        cycle must be element addr of A and B (read latency 1)
      if loading and rst = '0' then
        if prev_addr >= 0 and prev_addr < N*N then
          got := unsigned(std_logic_vector'(doutb(0) & doutb(1)));
          exp := a_el(prev_addr / N, prev_addr mod N);
          if got /= exp then
            eb := eb + 1;
            if eb <= 3 then
              say("  [BRAM->partitioner] A element " & integer'image(prev_addr) & ": read 0x" &
                  hex(got) & ", expected 0x" & hex(exp));
            end if;
          end if;
          got := unsigned(std_logic_vector'(doutb(3) & doutb(2)));
          exp := b_el(prev_addr / N, prev_addr mod N);
          if got /= exp then
            eb := eb + 1;
            if eb <= 3 then
              say("  [BRAM->partitioner] B element " & integer'image(prev_addr) & ": read 0x" &
                  hex(got) & ", expected 0x" & hex(exp));
            end if;
          end if;
        end if;
        if to_integer(unsigned(addrA12)) = N*N-1 and prev_addr = N*N-2 then t_lastaddr <= ns_now; end if;
        prev_addr := to_integer(unsigned(addrA12));
      end if;

      -- --- 2. partitioner -> multiplier: block pair (i,j,p), p fastest
      if p_valid = '1' and p_ready = '1' then
        loading := false;
        r := np mod 1000; i := r / 100; j := (r / 10) mod 10; p := r mod 10;
        if r = 0 then t_pair0 <= ns_now; pl_stage <= PL_MULT_ACC; end if;
        if r = 999 then t_pairN <= ns_now; pl_stage <= PL_DRAIN_WRITES; end if;
        for el in 0 to 24 loop
          if unsigned(A(el)) /= a_el(i*BLK + el/BLK, p*BLK + el mod BLK) or
             unsigned(Bm(el)) /= b_el(p*BLK + el/BLK, j*BLK + el mod BLK) then
            ep := ep + 1;
            if ep <= 3 then
              say("  [partitioner] pair " & integer'image(r) & " (i,j,p)=(" & integer'image(i) & "," &
                  integer'image(j) & "," & integer'image(p) & ") element " & integer'image(el) &
                  ": A=0x" & hex(A(el)) & " exp 0x" & hex(a_el(i*BLK + el/BLK, p*BLK + el mod BLK)) &
                  "  B=0x" & hex(Bm(el)) & " exp 0x" & hex(b_el(p*BLK + el/BLK, j*BLK + el mod BLK)));
            end if;
          end if;
        end loop;
        np := np + 1;
      end if;

      -- --- 3. multiplier -> accumulator
      if m_valid = '1' and m_ready = '1' then
        r := nm mod 1000; i := r / 100; j := (r / 10) mod 10; p := r mod 10;
        if r = 0 then t_mul0 <= ns_now; end if;
        if r = 999 then t_mulN <= ns_now; end if;
        for el in 0 to 24 loop
          exp := m_el(i, j, p, el);
          if unsigned(M(el)) /= exp then
            em := em + 1;
            if em <= 3 then
              say("  [multiplier] product " & integer'image(r) & " element " & integer'image(el) &
                  ": 0x" & hex(M(el)) & " expected 0x" & hex(exp));
            end if;
          end if;
        end loop;
        nm := nm + 1;
      end if;

      -- --- 4. accumulator -> RAM_INTERFACE (ap_fifo: empty_n & read)
      if c_valid = '1' and c_ready = '1' then
        bi := nk mod 100; i := bi / 10; j := bi mod 10;
        if bi = 0 then t_blk0 <= ns_now; end if;
        if bi = 99 then t_blkN <= ns_now; end if;
        for el in 0 to 24 loop
          word := (i*BLK + el/BLK) * N + j*BLK + el mod BLK;
          if unsigned(dout(64*el+63 downto 64*el)) /= CG(word) then
            ec := ec + 1;
            if ec <= 3 then
              say("  [accumulator] block " & integer'image(bi) & " element " & integer'image(el) &
                  ": 0x" & hex(dout(64*el+63 downto 64*el)) & " expected 0x" & hex(CG(word)));
            end if;
          end if;
        end loop;
        nk := nk + 1;
      end if;

      -- --- 5. AXI write address: one row of 5 values per block row; the
      --        m_axi adapter may split a row at a 4 KB boundary (legal AXI)
      if awvalid = '1' and awready = '1' then
        r := na mod 500; bi := r / 5; i := bi / 10; j := bi mod 10;     -- row r of this run
        word := (i*BLK + r mod 5) * N + j*BLK + (5 - row_left);
        if nrow = 0 and row_left = 5 then t_aw0 <= ns_now; end if;
        if unsigned(awaddr) /= unsigned(DDR_BASE) + to_unsigned(8*word, 64) or
           to_integer(unsigned(awlen)) + 1 > row_left then
          ea := ea + 1;
          if ea <= 3 then
            say("  [AXI AW] row " & integer'image(r) & ": burst to 0x" & hex(awaddr) & " len " &
                integer'image(to_integer(unsigned(awlen)) + 1) & ", expected 0x" &
                hex(unsigned(DDR_BASE) + to_unsigned(8*word, 64)) & " len <= " & integer'image(row_left));
          end if;
        end if;
        row_left := row_left - (to_integer(unsigned(awlen)) + 1);
        if row_left <= 0 then row_left := 5; na := na + 1; nrow := (nrow + 1) mod 500; end if;
        outst := outst + 1;
      end if;

      -- --- 6. AXI write data
      if wvalid = '1' and wready = '1' then
        r := nw mod 2500; bi := r / 25; e := r mod 25; i := bi / 10; j := bi mod 10;
        word := (i*BLK + e/BLK) * N + j*BLK + e mod BLK;
        if unsigned(wdata) /= CG(word) then
          ew := ew + 1;
          if ew <= 3 then
            say("  [AXI W] beat " & integer'image(r) & " (C word " & integer'image(word) & "): 0x" &
                hex(wdata) & " expected 0x" & hex(CG(word)));
          end if;
        end if;
        nw := nw + 1;
      end if;

      -- --- 7. AXI write response
      if bvalid = '1' and bready = '1' then
        if bresp /= "00" then
          er := er + 1;
          if er <= 3 then say("  [AXI B] response " & integer'image(nb mod 500) & ": BRESP=" & to_string(bresp) &
                              " (" & "11 = DECERR: no slave at that address)"); end if;
        end if;
        nb := nb + 1; outst := outst - 1;
      end if;

      -- --- done
      if done = '1' and done_d = '0' then t_done <= ns_now; pl_stage <= RESET; end if;
      done_d := done;

      -- --- utilisation inside a run (start pulse .. done)
      if in_run = '1' then
        cyc_run <= cyc_run + 1;
        if p_ready = '0' then cyc_mult_busy <= cyc_mult_busy + 1; end if;
        if m_valid = '1' and m_ready = '0' then cyc_acc_wait <= cyc_acc_wait + 1; end if;
        if c_valid = '1' and c_ready = '0' then cyc_writer_stall <= cyc_writer_stall + 1; end if;
        if outst > 0 then cyc_axi_busy <= cyc_axi_busy + 1; end if;
      end if;

      pairs <= np; muls <= nm; blks <= nk; aws <= na; beats <= nw; nresp <= nb;
      err_bram <= eb; err_part <= ep; err_mul <= em; err_acc <= ec;
      err_awaddr <= ea; err_wdata <= ew; err_bresp <= er;
      outstanding <= outst;
      if arvalid = '1' then report "unexpected AXI read" severity error; end if;
    end if;
  end process;

  stage <= pl_stage when cpu_stage = START_GPIO and pl_stage /= RESET else cpu_stage;

  -- interrupt: rising edge of done (GIC configured rising-edge) + ISR latency
  process(clk)
    variable d : std_logic := '0';
  begin
    if rising_edge(clk) then
      if done = '1' and d = '0' then
        irq_count <= irq_count + 1;
        t_isr  <= ns_now + T_IRQ_NS;
      end if;
      d := done;
    end if;
  end process;

  -- ===================== the application (helloworld.c, rung 3) =============
  cpu : process
    variable l : line;
    variable t_ld0, t_ld1, t_gpio, t_rb0, t_rb1, irq0 : integer;
    variable n_ok, n_poison, n_zero, n_other, tot_ok : integer;
    variable v : std_logic_vector(63 downto 0);
    variable p0, m0, k0, a0, w0, b0 : integer;
    variable e_b, e_p, e_m, e_c, e_a, e_w, e_r : integer;
    variable cyc0, mb0, ws0, ab0 : integer := 0;
    variable pl_ns : integer;

    procedure cpu_wr32(pidx : integer; word : integer; data : std_logic_vector(31 downto 0)) is
    begin
      addra <= word; dina <= data; wea(pidx) <= '1';
      wait until rising_edge(clk);
      wea(pidx) <= '0';
      wait for (T_BRAM_WR_NS - 10) * 1 ns;
    end procedure;

    procedure line2(name : string; t0, t1 : integer; note : string) is
    begin
      say("  " & pad(name, 46) & lpad(us2(t1 - t0), 9) & " us  " & lpad(integer'image((t1 - t0) / 10), 7) &
          " cyc  " & note);
    end procedure;

    procedure csv(run : integer; name : string; t0, t1 : integer) is
    begin
      say("CSV,stage," & integer'image(run) & "," & name & "," & integer'image(t0) & "," & integer'image(t1));
    end procedure;
  begin
    say("");
    say("=== rung 3 (partitioner v6 + writer fix) on the board model ===");
    say("DDR input of RAM_INTERFACE = 0x" & hex(DDR_BASE) & ", BRAM read latency = " & integer'image(BRAM_LAT) &
        ", DDR4 write latency = " & integer'image(LAT) & " cycles, CPU loads BRAMs = " &
        integer'image(CPU_LOADS_BRAM) & ", C filled with 0x" & hex(FILL_VAL) & " before each run");
    rst <= '1';
    for k in 1 to 16 loop wait until rising_edge(clk); end loop;
    rst <= '0';
    for k in 1 to 16 loop wait until rising_edge(clk); end loop;
    tot_ok := 0;

    for run in 1 to N_RUNS loop
      say("");
      say("--- run " & integer'image(run) & " ---");
      p0 := pairs; m0 := muls; k0 := blks; a0 := aws; w0 := beats; b0 := nresp;
      e_b := err_bram; e_p := err_part; e_m := err_mul; e_c := err_acc;
      e_a := err_awaddr; e_w := err_wdata; e_r := err_bresp;

      -- 1. load A and B into the BRAMs (bram_write_64: high word, then low word)
      t_ld0 := ns_now;
      cpu_stage <= CPU_LOAD_BRAM;
      if CPU_LOADS_BRAM = 1 then
        for k in 0 to N*N-1 loop
          v := std_logic_vector(a_el(k / N, k mod N));
          cpu_wr32(0, k, v(63 downto 32)); cpu_wr32(1, k, v(31 downto 0));
          v := std_logic_vector(b_el(k / N, k mod N));
          cpu_wr32(3, k, v(63 downto 32)); cpu_wr32(2, k, v(31 downto 0));
        end loop;
      end if;
      t_ld1 := ns_now;

      -- (not timed by the app) check_brams + clear C
      cpu_stage <= CPU_CLEAR_C;
      fill <= '1'; wait until rising_edge(clk); fill <= '0'; wait until rising_edge(clk);

      -- 2. start: toggle the GPIO (toggle2pulse makes the start pulse)
      irq0 := irq_count;
      cpu_stage <= START_GPIO;
      t_gpio := ns_now;
      wait for (T_GPIO_NS - 10) * 1 ns;
      wait until rising_edge(clk);
      cyc0 := cyc_run;
      in_run <= '1';
      gpio_start <= not gpio_start;

      -- 3. wait for the done interrupt (timeout 1 ms, as in the app)
      while irq_count = irq0 and ns_now - t_gpio < 1000000 loop
        wait until rising_edge(clk);
      end loop;
      in_run <= '0';
      cpu_stage <= IRQ_LATENCY;
      if irq_count = irq0 then
        say("  NO DONE INTERRUPT within 1 ms");
        wait for 1 us;
      else
        while ns_now < t_isr loop wait until rising_edge(clk); end loop;  -- ISR latency
      end if;

      -- 4. read C back from the PL DDR4
      t_rb0 := ns_now;
      cpu_stage <= CPU_READ_C;
      n_ok := 0; n_poison := 0; n_zero := 0; n_other := 0;
      for k in 0 to N*N-1 loop
        rd_addr <= k;
        wait until rising_edge(clk); wait until rising_edge(clk);
        if unsigned(rd_data) = CG(k) then n_ok := n_ok + 1;
        elsif rd_data = FILL_VAL then n_poison := n_poison + 1;
        elsif unsigned(rd_data) = 0 then n_zero := n_zero + 1;
        else n_other := n_other + 1; end if;
        wait for (T_DDR_RD_NS - 20) * 1 ns;
      end loop;
      t_rb1 := ns_now;
      cpu_stage <= CPU_CHECK;
      if run = 1 then
        mk_load0 <= t_ld0; mk_gpio <= t_gpio; mk_pulse <= t_pulse; mk_pair0 <= t_pair0;
        mk_pairN <= t_pairN; mk_done <= t_done; mk_isr <= t_isr; mk_rb0 <= t_rb0; mk_rb1 <= t_rb1;
      end if;
      if n_ok = N*N then tot_ok := tot_ok + 1; end if;

      -- ---------------- correctness, stage by stage ----------------
      say("  Data check per stage (first stage that is wrong = where it goes wrong):");
      say("    1 BRAM -> partitioner (A,B elements) : " & integer'image(err_bram - e_b) & " wrong");
      say("    2 partitioner blocks out  (" & integer'image(pairs - p0) & "/1000) : " &
          integer'image(err_part - e_p) & " wrong elements");
      say("    3 multiplier products     (" & integer'image(muls - m0) & "/1000) : " &
          integer'image(err_mul - e_m) & " wrong elements");
      say("    4 accumulator C blocks    (" & integer'image(blks - k0) & "/100)  : " &
          integer'image(err_acc - e_c) & " wrong elements");
      say("    5 AXI write rows (address)(" & integer'image(aws - a0) & "/500)  : " &
          integer'image(err_awaddr - e_a) & " wrong");
      say("    6 AXI write data          (" & integer'image(beats - w0) & "/2500): " &
          integer'image(err_wdata - e_w) & " wrong");
      say("    7 AXI write responses     (" & integer'image(nresp - b0) & " bursts): " &
          integer'image(err_bresp - e_r) & " not OKAY (DECERR = no slave there)");
      say("    8 C read back by the CPU             : " & integer'image(n_ok) & " correct, " &
          integer'image(n_poison) & " never written (still 0x" & hex(FILL_VAL) & "), " &
          integer'image(n_zero) & " zero, " & integer'image(n_other) & " other wrong");
      if n_decerr > 0 or n_outside_c > 0 then
        say("    AXI: " & integer'image(n_decerr) & " bursts DECERR, " & integer'image(n_outside_c) &
            " bursts outside C; first wrong address 0x" & hex(first_bad_addr));
      end if;
      say("  Interrupts this run: " & integer'image(irq_count - irq0));

      -- ---------------- timing, stage by stage ----------------
      pl_ns := t_done - t_pulse;
      say("");
      say("  Stage timing (CPU parts = model, PL parts = cycle-accurate RTL):");
      line2("A  CPU writes A,B into BRAMs (10000 x 32 bit)", t_ld0, t_ld1, "[model: " & integer'image(T_BRAM_WR_NS) & " ns/write]");
      line2("B  start: GPIO write -> toggle2pulse -> start", t_gpio, t_pulse, "[GPIO model + 2 cyc]");
      line2("C  PL: on-chip copy of A,B (LOAD, 2500 el.)", t_pulse, t_pair0, "");
      line2("D  PL: multiply + accumulate (1000 pairs)", t_pair0, t_pairN, "");
      line2("E  PL: last pair -> last product", t_pairN, t_mulN, "");
      line2("F  PL: last product -> last C block to writer", t_mulN, t_blkN, "");
      line2("G  PL: last C block -> done (last write resp.)", t_blkN, t_done, "");
      line2("   = PL total (start pulse -> done)", t_pulse, t_done, "");
      line2("   write-back span (first AW -> done)", t_aw0, t_done, "(overlaps D)");
      line2("H  done -> interrupt handler", t_done, t_isr, "[model]");
      line2("I  CPU reads C back (2500 x 64 bit)", t_rb0, t_rb1, "[model: " & integer'image(T_DDR_RD_NS) & " ns/read]");
      line2("   = app 'compute' (GPIO write -> ISR)", t_gpio, t_isr, "");
      line2("   = app end-to-end (load+compute+read-back)", t_ld0, t_ld1 + (t_isr - t_gpio) + (t_rb1 - t_rb0), "");
      say("  Inside the PL run (" & integer'image(cyc_run - cyc0) & " cycles):");
      say("    multiplier busy (not ready)         : " & integer'image(cyc_mult_busy - mb0) & " cycles");
      say("    write-back with bursts in flight    : " & integer'image(cyc_axi_busy - ab0) & " cycles");
      say("    accumulator waiting for the writer  : " & integer'image(cyc_writer_stall - ws0) & " cycles");
      csv(run, "A_cpu_bram_load", t_ld0, t_ld1);
      csv(run, "B_start", t_gpio, t_pulse);
      csv(run, "C_onchip_copy", t_pulse, t_pair0);
      csv(run, "D_mult_acc", t_pair0, t_pairN);
      csv(run, "E_last_product", t_pairN, t_mulN);
      csv(run, "F_last_block", t_mulN, t_blkN);
      csv(run, "G_last_write_done", t_blkN, t_done);
      csv(run, "W_writeback_span", t_aw0, t_done);
      csv(run, "H_irq", t_done, t_isr);
      csv(run, "I_cpu_readback", t_rb0, t_rb1);
      say("CSV,util," & integer'image(run) & "," & integer'image(cyc_run - cyc0) & "," &
          integer'image(cyc_mult_busy - mb0) & "," & integer'image(cyc_axi_busy - ab0) & "," &
          integer'image(cyc_writer_stall - ws0));
      say("CSV,check," & integer'image(run) & "," & integer'image(err_bram - e_b) & "," &
          integer'image(err_part - e_p) & "," & integer'image(err_mul - e_m) & "," &
          integer'image(err_acc - e_c) & "," & integer'image(err_awaddr - e_a) & "," &
          integer'image(err_wdata - e_w) & "," & integer'image(err_bresp - e_r) & "," &
          integer'image(n_ok) & "," & integer'image(n_poison) & "," & integer'image(n_zero) & "," &
          integer'image(n_other) & "," & integer'image(irq_count - irq0));
      mb0 := cyc_mult_busy; ws0 := cyc_writer_stall; ab0 := cyc_axi_busy;
    end loop;

    say("");
    if tot_ok = N_RUNS then say("RESULT: ALL " & integer'image(N_RUNS) & " RUNS CORRECT");
    else say("RESULT: " & integer'image(N_RUNS - tot_ok) & " of " & integer'image(N_RUNS) & " RUNS WRONG"); end if;
    sim_end <= true;
    wait;
  end process;
end architecture;
