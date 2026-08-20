-- scale_seq.vhd — EXERCISE: C-major scale sequencer feeding the NCO.
--
-- YOUR TASK: implement the architecture body. The testbench
-- (tb/scale_seq_tb.vhd) is complete and grades the requirements below:
--   run  make sim TB=scale_seq_tb   until every R* check passes.
--
-- Requirements:
--   R1: fcw steps through the 8 notes of the C major scale, in order,
--       wrapping C4 D4 E4 F4 G4 A4 B4 C5 -> C4 ... Each note's fcw must
--       give an output frequency within +/-0.5 Hz of equal temperament:
--       261.6256, 293.6648, 329.6276, 349.2282, 391.9954, 440.0000,
--       493.8833, 523.2511 Hz. note_idx reports the current position (0-7).
--   R2: while en='1', note_idx advances exactly every NOTE_CLKS clocks.
--   R3: synchronous active-high reset returns the sequencer to note 0
--       (full duration restarts).
--   R4: en='0' pauses everything — note_idx, fcw, and the note timer hold.
--
-- Hints:
--   * fcw for a note = round(f_note * 2**32 / CLK_HZ). All eight values are
--     < 2**18, so they fit in an integer: you can compute them at
--     elaboration time with ieee.math_real (integer(round(...))) inside a
--     constant table — synthesizable, because it evaluates before synthesis.
--   * You need: an array-of-unsigned table type, a note timer counter, and
--     a 3-bit note index. One clocked process handles all of it.
--   * Follow the house style (see nco.vhd): synchronous reset, clock
--     enable, no latches. Zero yosys warnings when you synthesize.
--
-- Radar analog: a stepped-frequency waveform scheduler — the same
-- structure that steps a DDS through an SFCW radar's frequency ladder.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
-- use ieee.math_real.all;   -- uncomment for the constant-table computation

entity scale_seq is
  generic (
    CLK_HZ    : positive := 12_000_000;
    NOTE_CLKS : positive := 6_000_000   -- 0.5 s per note on hardware
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;                  -- synchronous, active-high
    en       : in  std_logic;
    fcw      : out unsigned(31 downto 0);      -- to the NCO's fcw port
    note_idx : out unsigned(2 downto 0)        -- current scale position
  );
end entity scale_seq;

architecture rtl of scale_seq is
  -- TODO: note-table type and constant (see hints above)
  -- TODO: note timer and index signals
begin

  -- TODO: sequencing process

  -- Placeholders so the project analyzes before you start — replace them:
  fcw      <= (others => '0');
  note_idx <= (others => '0');

end architecture rtl;
