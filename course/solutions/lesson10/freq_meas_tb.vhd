-- freq_meas_tb.vhd — self-checking testbench for freq_meas, driven by
-- osc_model (the simulated hand-in-the-pitch-field).
--
-- Verification approach: osc_model (BASE_HZ = 200 kHz, DELTA_HZ = 20 kHz)
-- feeds freq_meas at f_clk = 12 MHz. The hand sweeps 0.0, 0.25, 0.5, 1.0;
-- for each position the TB waits for a valid strobe, discards that first
-- measurement (its window may straddle the hand movement), then checks the
-- next one against expected = EDGES * CLK_HZ / f_osc with f_osc =
-- BASE_HZ - hand*DELTA_HZ. Tolerance is +/-2 counts: each window edge is
-- quantized to a clk sampling instant (up to +/-1 clk between opening and
-- closing edges) and the expected value itself is generally non-integer.
--
-- Requirement tags (R1..R4 from freq_meas.vhd): one per hand position.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity freq_meas_tb is
end entity freq_meas_tb;

architecture sim of freq_meas_tb is
  constant CLK_HZ   : real     := 12_000_000.0;
  constant CLK_PER  : time     := 1 sec / 12_000_000;
  constant EDGES    : positive := 64;
  constant CNT_BITS : positive := 24;
  constant BASE_HZ  : real     := 200_000.0;
  constant DELTA_HZ : real     := 20_000.0;

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal hand   : real      := 0.0;
  signal sig    : std_logic;
  signal period : unsigned(CNT_BITS - 1 downto 0);
  signal valid  : std_logic;
  signal done   : boolean   := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  osc : entity work.osc_model
    generic map (
      BASE_HZ  => BASE_HZ,
      DELTA_HZ => DELTA_HZ
    )
    port map (
      hand    => hand,
      osc_out => sig
    );

  dut : entity work.freq_meas
    generic map (
      EDGES    => EDGES,
      CNT_BITS => CNT_BITS
    )
    port map (
      clk    => clk,
      rst    => rst,
      sig_in => sig,
      period => period,
      valid  => valid
    );

  main : process
    -- Block until the DUT strobes valid. Sampling right after
    -- rising_edge(clk) sees the strobe one clock late, which is harmless:
    -- 'period' holds until the next window completes ~4000 clocks later.
    procedure wait_valid is
    begin
      loop
        wait until rising_edge(clk);
        exit when valid = '1';
      end loop;
    end procedure;

    -- Move the hand, discard the straddling measurement, check the clean one.
    procedure check_hand(tag : string; hand_val : real) is
      variable f_osc    : real;
      variable expected : real;
      variable meas     : natural;
    begin
      hand <= hand_val;
      f_osc    := BASE_HZ - hand_val * DELTA_HZ;
      expected := real(EDGES) * CLK_HZ / f_osc;
      wait_valid;  -- window may straddle the hand movement: discard
      wait_valid;  -- entirely at the new frequency: check
      meas := to_integer(period);
      if abs(real(meas) - expected) <= 2.0 then
        report tag & " pass: hand=" & real'image(hand_val) &
               " period=" & integer'image(meas) &
               " expected~=" & real'image(expected);
      else
        assert false
          report tag & " FAIL: hand=" & real'image(hand_val) &
                 " period=" & integer'image(meas) &
                 " expected=" & real'image(expected)
          severity error;
      end if;
    end procedure;
  begin
    rst <= '1';
    for i in 1 to 4 loop
      wait until rising_edge(clk);
    end loop;
    rst <= '0';

    check_hand("R1", 0.0);   -- 200.0 kHz -> expected 3840.0
    check_hand("R2", 0.25);  -- 195.0 kHz -> expected ~3938.5
    check_hand("R3", 0.5);   -- 190.0 kHz -> expected ~4042.1
    check_hand("R4", 1.0);   -- 180.0 kHz -> expected ~4266.7

    report "freq_meas testbench complete (any FAILs are listed above)";
    -- osc_model free-runs forever (its pinned interface has no enable), so
    -- stopping the clock is not enough to drain the event queue: end the
    -- simulation explicitly.
    done <= true;
    std.env.finish;
  end process;

  -- Whole run is ~3 ms of simulated time; if valid never strobes, stop
  -- instead of hanging forever.
  watchdog : process
  begin
    wait until done for 10 ms;
    assert done
      report "TB FAIL: watchdog timeout - no valid strobe from freq_meas"
      severity failure;
    wait;
  end process;

end architecture sim;
