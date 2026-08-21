-- osc_model.vhd — SIMULATION-ONLY behavioural model of the antenna oscillator.
--
-- *** NOT SYNTHESIZABLE — do not include in any synthesis file list. ***
-- Real-valued generics/ports and time-based waits are fine in simulation;
-- yosys would reject every line of this. In hardware this block is the
-- 74HC14 relaxation oscillator on the breadboard (lesson99).
--
-- Model (documented contract, used by freq_meas_tb):
--   osc_out is a 50%-duty square wave at
--     f_osc = BASE_HZ - hand * DELTA_HZ    [Hz]
--   hand = 0.0 means the hand is far away (frequency = BASE_HZ);
--   hand = 1.0 means the hand is touching the antenna (maximum added
--   capacitance, frequency pulled down by the full DELTA_HZ). More hand
--   capacitance -> lower frequency, matching the physical oscillator.
--   'hand' is re-sampled at every output half-cycle, so a change takes
--   effect within one half-period (a few microseconds at these defaults).

library ieee;
use ieee.std_logic_1164.all;

entity osc_model is
  generic (
    BASE_HZ  : real := 200_000.0;  -- frequency with the hand fully away
    DELTA_HZ : real := 0.0         -- frequency pull at hand = 1.0
  );
  port (
    hand    : in  real;       -- 0.0 = far away .. 1.0 = touching the antenna
    osc_out : out std_logic
  );
end entity osc_model;

architecture sim of osc_model is
begin

  -- Free-running toggle: each pass emits one half-cycle at the frequency
  -- implied by the current 'hand', then re-samples.
  toggle : process
    variable f    : real;
    variable half : time;
    variable lvl  : std_logic := '0';
  begin
    f := BASE_HZ - hand * DELTA_HZ;
    assert f > 0.0
      report "osc_model: f_osc <= 0 Hz (check BASE_HZ, DELTA_HZ, hand)"
      severity failure;
    half := (0.5 / f) * 1 sec;
    osc_out <= lvl;
    lvl := not lvl;
    wait for half;
  end process;

end architecture sim;
