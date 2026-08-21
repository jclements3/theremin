-- theremin_top_tb.vhd — end-to-end integration testbench: the whole
-- instrument against the target model.
--
-- osc_model (BASE_HZ = 200 kHz, DELTA_HZ = 20 kHz — the lesson10 scenario)
-- drives theremin_top's osc_in; the "hand" moves through three positions
-- and the TB verifies the AUDIO OUTPUT tracks it — a pure black-box check
-- through the DUT's four real pins, exactly what the bench will see.
--
-- The audio fundamental is recovered from the delta-sigma BITSTREAM
-- itself: the bitstream is boxcar-filtered by an accumulate-and-dump over
-- BLK = 256 clocks (lesson12's trick: the block sum is a low-pass filter,
-- so the audio sine re-emerges from the 1-bit noise); a comparator with
-- +/-32-count hysteresis around midscale turns it into a clean square,
-- and the fundamental is timed over N whole cycles. The expected value is
-- computed independently in real math from the oscillator physics:
--   period  = EDGES * f_clk / f_osc          (freq_meas contract)
--   fcw     = FCW_BASE + (P_REF - period)*2**SHIFT   (pitch_map contract)
--   f_audio = fcw * f_clk / 2**32            (nco contract)
-- Tolerance 2%: +/-2 counts of period quantization is +/-128 fcw
-- (~0.15%), crossing quantization is one block = 21 us against audio
-- periods of ~4 ms, and smoothing dither adds a few fcw counts.
--
-- (A white-box fcw tap via a VHDL-2008 external name would be the other
-- legitimate probe; this GHDL build miscompiles external names into
-- sibling instances, so the TB stays strictly black-box.)
--
-- After each hand move the TB waits 25 ms: at ~2.9 kHz measurement rate
-- that is ~70 valid strobes, and pitch_map's 1/8-per-strobe smoothing has
-- long converged (residual < 2 fcw counts from the worst-case jump).
--
-- Requirement tags (R1..R5 from theremin_top.vhd):
--   R1: bitstream alive (both levels seen) within 2 ms of power-up — the
--       POR self-start, no external reset.
--   R2: hand = 0.0  -> audio ~= 261.6 Hz (C4: fcw = FCW_BASE = 93640)
--   R3: hand = 0.5  -> audio ~= 225.5 Hz (fcw ~= 80705)
--   R4: hand = 1.0  -> audio ~= 185.3 Hz (fcw ~= 66333)
--   R5: measured audio frequency strictly decreases as the hand
--       approaches: pitch tracks the hand end-to-end.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity theremin_top_tb is
end entity theremin_top_tb;

architecture sim of theremin_top_tb is
  constant CLK_HZ   : real     := 12_000_000.0;
  constant CLK_PER  : time     := 1 sec / 12_000_000;
  constant BASE_HZ  : real     := 200_000.0;
  constant DELTA_HZ : real     := 20_000.0;
  constant EDGES    : positive := 64;      -- must match theremin_top's freq_meas
  constant P_REF    : positive := 3840;    -- pitch_map defaults (pinned)
  constant FCW_BASE : positive := 93640;
  constant SHIFT    : natural  := 6;

  constant BLK  : positive := 256;  -- accumulate-and-dump block, 21.3 us
  constant HYST : positive := 32;   -- comparator hysteresis, counts of BLK

  signal clk   : std_logic := '0';
  signal hand  : real      := 0.0;
  signal osc   : std_logic;
  signal audio : std_logic;
  signal led   : std_logic;
  signal done  : boolean   := false;

  signal audio_hi     : boolean := false;  -- filtered + hysteresis comparator
  signal seen0, seen1 : boolean := false;  -- bitstream activity (R1)
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  u_osc : entity work.osc_model
    generic map (
      BASE_HZ  => BASE_HZ,
      DELTA_HZ => DELTA_HZ
    )
    port map (
      hand    => hand,
      osc_out => osc
    );

  dut : entity work.theremin_top
    port map (
      clk12     => clk,
      osc_in    => osc,
      audio_out => audio,
      led_hb    => led
    );

  -- R1 probe: has the delta-sigma bitstream shown both levels yet?
  activity : process (clk)
  begin
    if rising_edge(clk) then
      if audio = '1' then
        seen1 <= true;
      elsif audio = '0' then
        seen0 <= true;
      end if;
    end if;
  end process;

  -- Audio recovery: accumulate-and-dump boxcar over BLK clocks, then a
  -- midscale comparator with hysteresis. audio_hi is the sign of the
  -- filtered sine — its rising edges mark the audio fundamental.
  recover : process (clk)
    variable acc : natural range 0 to BLK := 0;
    variable n   : natural range 0 to BLK - 1 := 0;
  begin
    if rising_edge(clk) then
      if audio = '1' then
        acc := acc + 1;
      end if;
      if n = BLK - 1 then
        if acc >= BLK / 2 + HYST then
          audio_hi <= true;
        elsif acc <= BLK / 2 - HYST then
          audio_hi <= false;
        end if;
        acc := 0;
        n   := 0;
      else
        n := n + 1;
      end if;
    end if;
  end process;

  main : process
    -- Time N whole cycles of the recovered audio square, first->last
    -- rising crossing, and return the fundamental in Hz.
    procedure measure_audio(n_cyc : positive; f_meas : out real) is
      variable t0 : time;
    begin
      if audio_hi then
        wait until not audio_hi;
      end if;
      wait until audio_hi;
      t0 := now;
      for i in 1 to n_cyc loop
        wait until not audio_hi;
        wait until audio_hi;
      end loop;
      f_meas := real(n_cyc) * 1.0e9 / real((now - t0) / 1 ns);
    end procedure;

    -- Move the hand, let the measurement/smoothing chain settle, then
    -- check the audio fundamental against the physics-derived expectation.
    procedure check_hand(tag : string; hand_val : real; f_meas : out real) is
      variable p_exp   : real;  -- expected freq_meas period, clk counts
      variable fcw_exp : real;  -- expected pitch_map output
      variable f_exp   : real;  -- expected audio fundamental, Hz
      variable f       : real;
    begin
      hand  <= hand_val;
      p_exp   := real(EDGES) * CLK_HZ / (BASE_HZ - hand_val * DELTA_HZ);
      fcw_exp := real(FCW_BASE) + (real(P_REF) - p_exp) * real(2 ** SHIFT);
      f_exp   := fcw_exp * CLK_HZ / 2.0 ** 32;
      wait for 25 ms;  -- ~70 valid strobes: smoothing fully settled
      measure_audio(2, f);
      assert abs(f - f_exp) <= 0.02 * f_exp
        report tag & " FAIL: audio=" & real'image(f) &
               " Hz, expected=" & real'image(f_exp) & " Hz +/-2%"
        severity error;
      report tag & " pass: hand=" & real'image(hand_val) &
             " audio=" & real'image(f) &
             " Hz (exp~=" & real'image(f_exp) & " Hz," &
             " fcw~=" & real'image(fcw_exp) & ")";
      f_meas := f;
    end procedure;

    variable f_far, f_mid, f_near : real;
  begin
    -- R1: no external reset exists — the POR must self-start the chain.
    wait for 2 ms;
    assert seen0 and seen1
      report "R1 FAIL: audio_out not toggling within 2 ms of power-up"
      severity error;
    report "R1 pass: delta-sigma bitstream live within 2 ms of power-up (POR self-start)";

    check_hand("R2", 0.0, f_far);   -- 200 kHz -> C4, 261.6 Hz
    check_hand("R3", 0.5, f_mid);   -- 190 kHz -> ~225.5 Hz
    check_hand("R4", 1.0, f_near);  -- 180 kHz -> ~185.3 Hz

    -- R5: end-to-end tracking direction — more hand, lower note.
    assert f_far > f_mid and f_mid > f_near
      report "R5 FAIL: audio frequency not monotonic in hand position"
      severity error;
    report "R5 pass: audio tracks hand monotonically: " &
           real'image(f_far) & " > " & real'image(f_mid) &
           " > " & real'image(f_near) & " Hz";

    report "theremin_top testbench complete (any FAILs are listed above)";
    -- osc_model free-runs forever: end the simulation explicitly.
    done <= true;
    std.env.finish;
  end process;

  -- Whole run is ~110 ms of simulated time; stop instead of hanging if the
  -- recovered audio never crosses (measure_audio would wait forever).
  watchdog : process
  begin
    wait until done for 500 ms;
    assert done
      report "TB FAIL: watchdog timeout - no recovered audio crossings"
      severity failure;
    wait;
  end process;

end architecture sim;
