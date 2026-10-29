-- Performance testbench (copy of tb_chain.vhd + passive handshake monitors).
-- The design is not changed; the monitors only watch valid/ready signals and
-- report cycle counts per stage as "PERF key=value" lines.
-- Testbench for the PL data path of accu_to_DDR:
--   BRAM model -> matrix_partitioner_B -> matrix_to_ports x2 -> MatMul5x5_PAR_IF
--   -> MatMul5x5_Accumulator -> concat -> RAM_INTERFACE model (ap_fifo handshake)
-- Input matrices are read from a_b.hex (A then B, 2500 x 64-bit each, row major).
-- The 50x50 result is written to c_out.hex for comparison in Python.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_chain_perf is
  generic (WRITE_BUSY_CYCLES : integer := 30);  -- time the RAM_INTERFACE model is busy per block
end entity;

architecture sim of tb_chain_perf is
  constant N : integer := 50;
  type mem_t is array (0 to N*N-1) of std_logic_vector(63 downto 0);
  signal memA, memB, memC : mem_t := (others => (others => '0'));

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal start : std_logic := '0';
  signal finished : boolean := false;

  signal addrA, addrB : std_logic_vector(11 downto 0);
  signal hiA, loA, hiB, loB : std_logic_vector(31 downto 0) := (others => '0');
  signal outA, outB : std_logic_vector(1599 downto 0);
  signal p_valid, p_ready : std_logic;

  type v64_arr is array (0 to 24) of std_logic_vector(63 downto 0);
  signal A, Bm, M, C : v64_arr;
  signal m_valid, m_ready, c_valid, c_ready : std_logic;
  signal dout : std_logic_vector(1599 downto 0);

  signal busy : integer := 0;
  signal blocks_written : integer := 0;
  signal cycles : integer := 0;
  signal win : std_logic := '0';   -- '1' from the start pulse until the 100th block is written
begin
  clk <= not clk after 5 ns when not finished;

  -- load matrices
  process
    file f : text open read_mode is "a_b.hex";
    variable l : line; variable v : std_logic_vector(63 downto 0);
  begin
    for k in 0 to N*N-1 loop readline(f, l); hread(l, v); memA(k) <= v; end loop;
    for k in 0 to N*N-1 loop readline(f, l); hread(l, v); memB(k) <= v; end loop;
    wait;
  end process;

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

  -- RAM_INTERFACE model with the new ap_fifo interface:
  -- data_read is asserted combinationally while idle and data is available.
  c_ready <= '1' when (c_valid = '1' and busy = 0 and rst = '0') else '0';

  process(clk)
    variable bx, by : integer := 0;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        busy <= 0;
      elsif busy > 0 then
        busy <= busy - 1;
      elsif c_valid = '1' and c_ready = '1' then
        for i in 0 to 4 loop
          for j in 0 to 4 loop
            memC((by*5+i)*N + bx*5 + j) <= dout(64*(i*5+j)+63 downto 64*(i*5+j));
          end loop;
        end loop;
        blocks_written <= blocks_written + 1;
        if bx = 9 then bx := 0; by := by + 1; else bx := bx + 1; end if;
        busy <= WRITE_BUSY_CYCLES;
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------------
  -- Passive performance monitors
  -- ---------------------------------------------------------------------
  process(clk)
    variable cyc : integer := 0;
    -- partitioner -> multiplier
    variable n_p, p_last, p_first, p_gap_min, p_gap_max, p_stall : integer := 0;
    -- multiplier
    variable mm_busy, mm_lat_min, mm_lat_max, p_take : integer := 0;
    variable mm_wait : boolean := false;
    -- multiplier -> accumulator
    variable n_m, m_stall : integer := 0;
    -- accumulator -> writer
    variable n_c, c_first, c_last, c_gap_min, c_gap_max, c_stall, wr_busy : integer := 0;
    variable reported : boolean := false;
    variable l : line;
  begin
    if rising_edge(clk) then
      if win = '1' then
        cyc := cyc + 1;
        -- block pair handed from partitioner to multiplier
        if p_valid = '1' and p_ready = '1' then
          n_p := n_p + 1;
          if n_p = 1 then p_first := cyc;
          else
            if n_p = 2 or cyc - p_last < p_gap_min then p_gap_min := cyc - p_last; end if;
            if cyc - p_last > p_gap_max then p_gap_max := cyc - p_last; end if;
          end if;
          p_last := cyc; p_take := cyc; mm_wait := true;
        end if;
        if p_valid = '1' and p_ready = '0' then p_stall := p_stall + 1; end if;
        -- multiplier busy = not ready for a new block pair
        if p_ready = '0' then mm_busy := mm_busy + 1; end if;
        -- multiplier latency: block pair accepted -> product valid
        if mm_wait and m_valid = '1' then
          if mm_lat_min = 0 or cyc - p_take < mm_lat_min then mm_lat_min := cyc - p_take; end if;
          if cyc - p_take > mm_lat_max then mm_lat_max := cyc - p_take; end if;
          mm_wait := false;
        end if;
        -- product handed to the accumulator
        if m_valid = '1' and m_ready = '1' then n_m := n_m + 1; end if;
        if m_valid = '1' and m_ready = '0' then m_stall := m_stall + 1; end if;
        -- finished 5x5 output block handed to the writer
        if c_valid = '1' and c_ready = '1' then
          n_c := n_c + 1;
          if n_c = 1 then c_first := cyc;
          else
            if n_c = 2 or cyc - c_last < c_gap_min then c_gap_min := cyc - c_last; end if;
            if cyc - c_last > c_gap_max then c_gap_max := cyc - c_last; end if;
          end if;
          c_last := cyc;
        end if;
        if c_valid = '1' and c_ready = '0' then c_stall := c_stall + 1; end if;
        if busy > 0 then wr_busy := wr_busy + 1; end if;
      elsif cyc > 0 and not reported then
        reported := true;
        write(l, string'("PERF total_cycles=") & integer'image(cyc)); writeline(output, l);
        write(l, string'("PERF block_pairs=") & integer'image(n_p)); writeline(output, l);
        write(l, string'("PERF first_pair_cycle=") & integer'image(p_first)); writeline(output, l);
        write(l, string'("PERF pair_interval_min=") & integer'image(p_gap_min)); writeline(output, l);
        write(l, string'("PERF pair_interval_max=") & integer'image(p_gap_max)); writeline(output, l);
        write(l, string'("PERF pair_interval_avg_x100=") & integer'image(((p_last - p_first) * 100) / (n_p - 1))); writeline(output, l);
        write(l, string'("PERF partitioner_stalled_cycles=") & integer'image(p_stall)); writeline(output, l);
        write(l, string'("PERF multiplier_busy_cycles=") & integer'image(mm_busy)); writeline(output, l);
        write(l, string'("PERF multiplier_latency_min=") & integer'image(mm_lat_min)); writeline(output, l);
        write(l, string'("PERF multiplier_latency_max=") & integer'image(mm_lat_max)); writeline(output, l);
        write(l, string'("PERF products=") & integer'image(n_m)); writeline(output, l);
        write(l, string'("PERF multiplier_stalled_cycles=") & integer'image(m_stall)); writeline(output, l);
        write(l, string'("PERF output_blocks=") & integer'image(n_c)); writeline(output, l);
        write(l, string'("PERF first_block_cycle=") & integer'image(c_first)); writeline(output, l);
        write(l, string'("PERF last_block_cycle=") & integer'image(c_last)); writeline(output, l);
        write(l, string'("PERF block_interval_min=") & integer'image(c_gap_min)); writeline(output, l);
        write(l, string'("PERF block_interval_max=") & integer'image(c_gap_max)); writeline(output, l);
        write(l, string'("PERF accumulator_stalled_cycles=") & integer'image(c_stall)); writeline(output, l);
        write(l, string'("PERF writer_busy_cycles=") & integer'image(wr_busy)); writeline(output, l);
      end if;
    end if;
  end process;

  -- stimulus and result dump
  process
    file fo : text open write_mode is "c_out.hex";
    variable l : line;
  begin
    rst <= '1';
    wait for 100 ns;
    wait until rising_edge(clk);
    rst <= '0';
    wait for 50 ns;
    wait until rising_edge(clk);
    start <= '1';
    win <= '1';
    wait until rising_edge(clk);
    start <= '0';
    while blocks_written < 100 and cycles < 400000 loop
      wait until rising_edge(clk);
      cycles <= cycles + 1;
    end loop;
    win <= '0';
    -- wait a while to make sure no extra (duplicate) blocks arrive
    for k in 0 to 3000 loop wait until rising_edge(clk); end loop;
    report "blocks_written=" & integer'image(blocks_written) & " cycles=" & integer'image(cycles);
    for k in 0 to N*N-1 loop hwrite(l, memC(k)); writeline(fo, l); end loop;
    finished <= true;
    wait;
  end process;
end architecture;
