-- Simple AXI4 write-only slave memory model for simulation.
--  * accepts up to 4 outstanding write addresses (INCR bursts, 64-bit beats)
--  * WREADY high once a burst address is queued; low every W_STALL_N-th cycle if W_STALL_N > 0
--  * each write response is given B_LATENCY cycles after the burst's WLAST
--  * byte strobes are honoured; 'dump' writes the memory to c_out.hex, 'clear' zeroes it
--  * counts bursts, beats and the burst-length range
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity axi_mem_model is
  generic (WORDS : integer := 2500; B_LATENCY : integer := 20; W_STALL_N : integer := 0);
  port (
    clk, rst : in std_logic;
    awvalid : in std_logic; awready : out std_logic;
    awaddr : in std_logic_vector(63 downto 0); awlen : in std_logic_vector(7 downto 0);
    wvalid : in std_logic; wready : out std_logic;
    wdata : in std_logic_vector(63 downto 0); wstrb : in std_logic_vector(7 downto 0); wlast : in std_logic;
    bvalid : out std_logic; bready : in std_logic;
    dump  : in std_logic;
    clear : in std_logic := '0';   -- zero the whole memory (between runs)
    n_bursts, n_beats, len_min, len_max : out integer;
    max_outstanding : out integer);
end entity;

architecture sim of axi_mem_model is
  type mem_t is array (0 to WORDS-1) of std_logic_vector(63 downto 0);
  type int_arr is array (0 to 15) of integer;
  signal wready_i : std_logic := '0';
  signal awready_i : std_logic := '0';
begin
  wready <= wready_i;
  awready <= awready_i;

  process(clk)
    variable mem : mem_t := (others => (others => '0'));
    variable aq_addr, aq_len : int_arr;          -- address queue
    variable aq_n : integer := 0;
    variable bq_due : int_arr;                   -- response queue (due cycle)
    variable bq_n : integer := 0;
    variable cur_addr, cur_beat : integer := 0;
    variable cyc : integer := 0;
    variable bursts, beats, lmin, lmax : integer := 0;
    variable bv : std_logic := '0';
    variable resp_done, maxo : integer := 0;
    variable w : std_logic_vector(63 downto 0);
    variable l : line;
    file fo : text;
  begin
    if rising_edge(clk) then
      cyc := cyc + 1;
      if rst = '1' then
        aq_n := 0; bq_n := 0; cur_beat := 0; bv := '0';
      else
        -- write response handshake (from the previous cycle's BVALID)
        if bv = '1' and bready = '1' then
          for q in 0 to 14 loop bq_due(q) := bq_due(q+1); end loop;
          bq_n := bq_n - 1; resp_done := resp_done + 1;
        end if;
        -- write address
        if awvalid = '1' and awready_i = '1' then
          aq_addr(aq_n) := to_integer(unsigned(awaddr(31 downto 3)));
          aq_len(aq_n) := to_integer(unsigned(awlen)) + 1;
          if bursts = 0 or aq_len(aq_n) < lmin then lmin := aq_len(aq_n); end if;
          if aq_len(aq_n) > lmax then lmax := aq_len(aq_n); end if;
          aq_n := aq_n + 1; bursts := bursts + 1;
          if bursts - resp_done > maxo then maxo := bursts - resp_done; end if;
        end if;
        -- write data
        if wvalid = '1' and wready_i = '1' and aq_n > 0 then
          w := mem((aq_addr(0) + cur_beat) mod WORDS);
          for b in 0 to 7 loop
            if wstrb(b) = '1' then w(8*b+7 downto 8*b) := wdata(8*b+7 downto 8*b); end if;
          end loop;
          mem((aq_addr(0) + cur_beat) mod WORDS) := w;
          beats := beats + 1;
          cur_beat := cur_beat + 1;
          if wlast = '1' then
            assert cur_beat = aq_len(0) report "WLAST does not match AWLEN" severity error;
            bq_due(bq_n) := cyc + B_LATENCY; bq_n := bq_n + 1;
            for q in 0 to 14 loop aq_addr(q) := aq_addr(q+1); aq_len(q) := aq_len(q+1); end loop;
            aq_n := aq_n - 1; cur_beat := 0;
          end if;
        end if;
        -- BVALID for the oldest response once it is due
        if bq_n > 0 and cyc >= bq_due(0) then bv := '1'; else bv := '0'; end if;
      end if;
      bvalid <= bv;
      if rst = '0' and aq_n < 4 then awready_i <= '1'; else awready_i <= '0'; end if;
      -- data only once its burst address is known (simplification, allowed by AXI)
      if rst = '1' or aq_n = 0 or (W_STALL_N > 0 and (cyc mod W_STALL_N) = 0) then wready_i <= '0';
      else wready_i <= '1'; end if;
      max_outstanding <= maxo; n_bursts <= bursts; n_beats <= beats; len_min <= lmin; len_max <= lmax;
      if clear = '1' then mem := (others => (others => '0')); end if;
      if dump = '1' then
        file_open(fo, "c_out.hex", write_mode);
        for k in 0 to WORDS-1 loop hwrite(l, mem(k)); writeline(fo, l); end loop;
        file_close(fo);
      end if;
    end if;
  end process;
end architecture;
