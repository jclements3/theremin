-- freq_meas.vhd — reciprocal period counter for the antenna oscillator.
--
-- Counts the number of clk cycles spanning EDGES rising edges of sig_in:
-- the window opens on a rising edge and closes on the EDGES-th rising edge
-- after it, so 'period' = EDGES full input periods measured in clk cycles
-- (nominal: EDGES * f_clk / f_sig). 'valid' strobes for exactly one clk per
-- completed measurement; the closing edge immediately opens the next window,
-- so measurements are back-to-back with no dead time.
--
-- sig_in must already be synchronous to clk (run it through sync_2ff,
-- lesson09, before this block); edge detection here is a plain registered
-- compare, not a synchronizer.
--
-- Requirements this module implements (verified in freq_meas_tb.vhd, which
-- drives it from osc_model with f_osc = BASE_HZ - hand*DELTA_HZ, BASE_HZ =
-- 200 kHz, DELTA_HZ = 20 kHz, f_clk = 12 MHz; each check allows +/-2 counts
-- for edge-sampling quantization):
--   R1: hand = 0.0  -> period ~= EDGES * f_clk / 200.0 kHz
--   R2: hand = 0.25 -> period ~= EDGES * f_clk / 195.0 kHz
--   R3: hand = 0.5  -> period ~= EDGES * f_clk / 190.0 kHz
--   R4: hand = 1.0  -> period ~= EDGES * f_clk / 180.0 kHz
--
-- Radar analog: EDGES is the dwell (integration) time. Doubling EDGES
-- doubles the measurement time and halves the relative quantization error —
-- exactly the dwell-vs-Doppler-resolution trade in a CW radar's CPI.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity freq_meas is
  generic (
    EDGES    : positive := 64;  -- input rising edges per measurement window
    CNT_BITS : positive := 24   -- width of the cycle counter / period output
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;     -- synchronous, active-high
    sig_in : in  std_logic;     -- synchronous input (post-sync_2ff)
    period : out unsigned(CNT_BITS - 1 downto 0);
    valid  : out std_logic      -- 1-clk strobe per completed measurement
  );
end entity freq_meas;

architecture rtl of freq_meas is
  signal sig_q     : std_logic := '0';  -- previous sig_in sample (edge detect)
  signal running   : std_logic := '0';  -- a window is open
  signal edge_cnt  : natural range 0 to EDGES - 1 := 0;  -- edges seen since open
  signal cycle_cnt : unsigned(CNT_BITS - 1 downto 0) := (others => '0');
begin

  measure : process (clk)
    variable rising : boolean;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        sig_q     <= '0';
        running   <= '0';
        edge_cnt  <= 0;
        cycle_cnt <= (others => '0');
        period    <= (others => '0');
        valid     <= '0';
      else
        valid  <= '0';
        sig_q  <= sig_in;
        rising := sig_in = '1' and sig_q = '0';

        if running = '0' then
          -- Idle: the first rising edge opens the window. cycle_cnt starts
          -- at 1 so that when the closing edge is detected P clocks later,
          -- cycle_cnt reads exactly P.
          if rising then
            running   <= '1';
            edge_cnt  <= 0;
            cycle_cnt <= to_unsigned(1, CNT_BITS);
          end if;
        else
          cycle_cnt <= cycle_cnt + 1;
          if rising then
            if edge_cnt = EDGES - 1 then
              -- EDGES-th edge since the window opened: publish and let this
              -- same edge open the next window (back-to-back measurement).
              period    <= cycle_cnt;
              valid     <= '1';
              edge_cnt  <= 0;
              cycle_cnt <= to_unsigned(1, CNT_BITS);
            else
              edge_cnt <= edge_cnt + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
