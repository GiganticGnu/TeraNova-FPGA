-- =============================================================================
-- rung_core (BRAM version, rungs 0-3)  --  Vivado/XSim copy of tb_chain_rtl.vhd
-- TeraNova FPGA project, Kai Janssen, Nov 2026.
--
-- The PL data path of one rung, exactly as in sim/tb_chain_rtl.vhd:
--   BRAM model -> matrix_partitioner_B -> matrix_to_ports x2 -> MatMul5x5_PAR_IF
--   -> MatMul5x5_Accumulator -> RAM_INTERFACE (real HLS RTL) -> AXI4 memory model
-- Differences with tb_chain_rtl (the design itself is NOT changed):
--   * clock, reset and start come in through ports, so tb_ladder can run all
--     rungs side by side on one clock;
--   * A and B come from tn_pkg instead of a_b.hex;
--   * the result is read back from the memory model and checked here
--     (instead of c_out.hex + Python).
-- This file is compiled once into every rung library (rung0..rung3); "work"
-- then means that rung's own partitioner and RAM_INTERFACE.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library tn_common;
use tn_common.tn_pkg.all;

entity rung_core is
  generic (B_LATENCY : integer := 20);          -- AXI memory latency L (cycles)
  port (
    clk, rst, start : in  std_logic;
    busy       : out std_logic;                 -- '1' from start until done (= the PL run time)
    done_o     : out std_logic;                 -- RAM_INTERFACE done
    pl_cycles  : out integer;                   -- cycles counted so far (live), final = PL run time
    mult_busy  : out integer;                   -- cycles the multiplier was busy (not ready)
    blocks     : out integer;                   -- 5x5 output blocks handed to the writer
    t_done_ns  : out integer;                   -- simulation time (ns) at which done was seen
    checked    : out std_logic;                 -- '1' when the result check has finished
    errors     : out integer);                  -- wrong result words (0 = PASS)
end entity;

architecture sim of rung_core is
  type mem_t is array (0 to N*N-1) of std_logic_vector(63 downto 0);
  function init_a return mem_t is variable m : mem_t; begin
    for k in 0 to N*N-1 loop m(k) := a_val(k); end loop; return m; end function;
  function init_b return mem_t is variable m : mem_t; begin
    for k in 0 to N*N-1 loop m(k) := b_val(k); end loop; return m; end function;
  constant memA : mem_t := init_a;
  constant memB : mem_t := init_b;
  signal addrA, addrB : std_logic_vector(11 downto 0);
  signal hiA, loA, hiB, loB : std_logic_vector(31 downto 0) := (others => '0');

  signal done : std_logic := '0';
  signal done_v : std_logic_vector(0 downto 0);
  signal rst_n, dump, clear : std_logic := '0';
  signal awvalid, awready, wvalid, wready, wlast, bvalid, bready, arvalid : std_logic;
  signal awaddr : std_logic_vector(63 downto 0);
  signal awlen : std_logic_vector(7 downto 0);
  signal wdata : std_logic_vector(63 downto 0);
  signal wstrb : std_logic_vector(7 downto 0);
  signal n_bursts, n_beats, len_min, len_max, max_out : integer;
  signal outA, outB : std_logic_vector(1599 downto 0);
  signal p_valid, p_ready : std_logic;
  type v64_arr is array (0 to 24) of std_logic_vector(63 downto 0);
  signal A, Bm, M, C : v64_arr;
  signal m_valid, m_ready, c_valid, c_ready : std_logic;
  signal dout : std_logic_vector(1599 downto 0);
  signal blocks_written : integer := 0;
  signal busy_i : std_logic := '0';
  signal rd_addr : integer := 0;
  signal rd_data : std_logic_vector(63 downto 0);
begin
  -- BRAM port B model: read latency 1, 64-bit value split in high/low 32-bit memories
  process(clk) begin
    if rising_edge(clk) then
      hiA <= memA(to_integer(unsigned(addrA)) mod (N*N))(63 downto 32);
      loA <= memA(to_integer(unsigned(addrA)) mod (N*N))(31 downto 0);
      hiB <= memB(to_integer(unsigned(addrB)) mod (N*N))(63 downto 32);
      loB <= memB(to_integer(unsigned(addrB)) mod (N*N))(31 downto 0);
    end if;
  end process;

  part : entity work.matrix_partitioner_B
    port map (clk => clk, rst => rst, start => start,
              bram_addr_A => addrA, bram_addr_B => addrB,
              data_in_highA => hiA, data_in_lowA => loA,
              data_in_highB => hiB, data_in_lowB => loB,
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

  -- ilconcat: In0 is the least significant word
  gen_cat : for e in 0 to 24 generate
    dout(64*e+63 downto 64*e) <= C(e);
  end generate;

  -- REAL RAM_INTERFACE (HLS RTL), ap_fifo input = accumulator handshake
  rst_n <= not rst;
  ri : entity work.RAM_INTERFACE
    port map (ap_clk => clk, ap_rst_n => rst_n,
      m_axi_gmem_AWVALID => awvalid, m_axi_gmem_AWREADY => awready, m_axi_gmem_AWADDR => awaddr,
      m_axi_gmem_AWID => open, m_axi_gmem_AWLEN => awlen, m_axi_gmem_AWSIZE => open, m_axi_gmem_AWBURST => open,
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
      m_axi_gmem_BVALID => bvalid, m_axi_gmem_BREADY => bready, m_axi_gmem_BRESP => "00",
      m_axi_gmem_BID => "0", m_axi_gmem_BUSER => "0",
      DDR => (others => '0'),
      data_dout => dout, data_empty_n => c_valid, data_read => c_ready,
      done => done_v);
  done <= done_v(0);

  mem : entity work.axi_mem_model
    generic map (WORDS => N*N, B_LATENCY => B_LATENCY, W_STALL_N => 0)
    port map (clk => clk, rst => rst,
      awvalid => awvalid, awready => awready, awaddr => awaddr, awlen => awlen,
      wvalid => wvalid, wready => wready, wdata => wdata, wstrb => wstrb, wlast => wlast,
      bvalid => bvalid, bready => bready,
      dump => dump, clear => clear, n_bursts => n_bursts, n_beats => n_beats,
      len_min => len_min, len_max => len_max, max_outstanding => max_out,
      rd_addr => rd_addr, rd_data => rd_data);


  -- count accepted output blocks (handshake on the ap_fifo input)
  process(clk) begin
    if rising_edge(clk) then
      if c_valid = '1' and c_ready = '1' then blocks_written <= blocks_written + 1; end if;
      if arvalid = '1' then report "unexpected AXI read" severity error; end if;
    end if;
  end process;
  blocks <= blocks_written;
  busy   <= busy_i;
  done_o <= done;

  -- multiplier utilisation: cycles in which the multiplier is not ready (busy)
  process(clk)
    variable nb : integer := 0;
  begin
    if rising_edge(clk) then
      if busy_i = '1' and p_ready = '0' then nb := nb + 1; end if;
      mult_busy <= nb;
    end if;
  end process;

  -- PL run time: counted exactly like tb_chain_rtl (start pulse -> done),
  -- then the 2500 result words are read back from the memory model and checked.
  process
    variable cnt, err, k, w : integer := 0;   -- (not 'n': VHDL is case-insensitive, N is the matrix size)
  begin
    pl_cycles <= 0; errors <= 0; checked <= '0'; t_done_ns <= 0;
    wait until rising_edge(clk) and start = '1';
    busy_i <= '1';
    while done = '0' and cnt < 400000 loop
      wait until rising_edge(clk);
      cnt := cnt + 1;
      pl_cycles <= cnt;
    end loop;
    busy_i <= '0';
    t_done_ns <= now / 1 ns;
    -- wait a while to make sure no extra (duplicate) blocks arrive
    w := 0;
    while w <= 3000 loop wait until rising_edge(clk); w := w + 1; end loop;
    -- read back and check C = A x B (plain while loop: one loop variable per loop)
    k := 0;
    while k < N*N loop
      rd_addr <= k;
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      if rd_data /= c_expected(k) then
        if err < 5 then
          report "result word " & integer'image(k) & " is wrong" severity error;
        end if;
        err := err + 1;
      end if;
      k := k + 1;
    end loop;
    if blocks_written /= 100 then
      report integer'image(blocks_written) & " output blocks instead of 100" severity error;
      err := err + 1;
    end if;
    errors <= err;
    checked <= '1';
    wait;
  end process;
end architecture;
