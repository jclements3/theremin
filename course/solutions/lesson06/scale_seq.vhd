-- scale_seq.vhd — C-major scale sequencer feeding the NCO.
--
-- Requirements this module implements (verified in scale_seq_tb.vhd):
--   R1: fcw steps through the 8 notes of the C major scale, in order,
--       wrapping C4 D4 E4 F4 G4 A4 B4 C5 -> C4 ... Each note's fcw gives
--       an output frequency within +/-0.5 Hz of equal temperament:
--       261.6256, 293.6648, 329.6276, 349.2282, 391.9954, 440.0000,
--       493.8833, 523.2511 Hz. note_idx reports the current position (0-7).
--   R2: while en='1', note_idx advances exactly every NOTE_CLKS clocks.
--   R3: synchronous active-high reset returns the sequencer to note 0
--       (full duration restarts).
--   R4: en='0' pauses everything — note_idx, fcw, and the note timer hold.
--
-- fcw for a note = round(f_note * 2**32 / CLK_HZ), computed at elaboration
-- time with math_real: real math is evaluated before synthesis, so only the
-- eight resulting integer constants reach the netlist. All eight are
-- < 2**18, safely inside integer range.
--
-- Radar analog: a stepped-frequency waveform scheduler — the same
-- structure that steps a DDS through an SFCW radar's frequency ladder.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

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
  type fcw_table_t is array (0 to 7) of unsigned(31 downto 0);

  -- Elaboration-time note -> frequency control word conversion.
  function note_fcw(f_hz : real) return unsigned is
  begin
    return to_unsigned(integer(round(f_hz * 2.0 ** 32 / real(CLK_HZ))), 32);
  end function;

  constant SCALE : fcw_table_t :=
    (note_fcw(261.6256),   -- C4
     note_fcw(293.6648),   -- D4
     note_fcw(329.6276),   -- E4
     note_fcw(349.2282),   -- F4
     note_fcw(391.9954),   -- G4
     note_fcw(440.0000),   -- A4
     note_fcw(493.8833),   -- B4
     note_fcw(523.2511));  -- C5

  signal timer : natural range 0 to NOTE_CLKS - 1 := 0;
  signal idx   : unsigned(2 downto 0)             := (others => '0');
begin

  sequencer : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        timer <= 0;
        idx   <= (others => '0');
      elsif en = '1' then
        if timer = NOTE_CLKS - 1 then
          timer <= 0;
          idx   <= idx + 1;  -- 3 bits: wraps 7 -> 0, C5 back to C4
        else
          timer <= timer + 1;
        end if;
      end if;
    end if;
  end process;

  fcw      <= SCALE(to_integer(idx));
  note_idx <= idx;

end architecture rtl;
