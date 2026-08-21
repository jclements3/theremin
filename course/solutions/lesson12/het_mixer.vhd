-- het_mixer.vhd — heterodyne mixer: XOR product detector + accumulate-and-dump.
--
-- Requirements this module implements (verified in het_mixer_tb.vhd):
--   R1: with rf_in and lo_in square waves offset in frequency by df, if_out
--       oscillates at the beat (difference) frequency df: it is the count of
--       clocks in each 2**ACC_LOG2-clock window during which rf_in /= lo_in,
--       which sweeps 0..2**ACC_LOG2 as the RF/LO phase difference slews.
--   R2: with rf_in and lo_in at the same frequency, if_out settles to a
--       constant proportional to their phase difference (no beat — the mixer
--       degenerates into a phase detector).
--
-- Why XOR: a square wave is a +/-1 signal in disguise ('0' = -1, '1' = +1),
-- and for such signals multiplication IS exclusive-nor; XOR gives the same
-- product with a sign flip, which only inverts the DC sense of if_out.
-- Multiplying two tones yields sum and difference frequencies; the
-- accumulate-and-dump window is a boxcar low-pass that crushes the ~2*f_rf
-- sum product and keeps the audio-rate difference. if_out needs
-- ACC_LOG2 + 1 bits because a window of all-ones counts to exactly
-- 2**ACC_LOG2.
--
-- rf_in/lo_in are sampled directly in the clk domain: in this lesson both
-- come from on-chip NCOs. A real antenna oscillator would pass through
-- sync_2ff (lesson09) first.
--
-- Radar analog: this is downconversion to an IF, the front half of every
-- superheterodyne receiver — and the reason a theremin is a CW radar: the
-- audible note IS the IF of a hand-tuned oscillator beaten against a
-- reference.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity het_mixer is
  generic (
    ACC_LOG2 : positive := 10  -- accumulate-and-dump window = 2**ACC_LOG2 clocks
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;  -- synchronous, active-high
    rf_in  : in  std_logic;  -- "antenna" oscillator (RF port)
    lo_in  : in  std_logic;  -- reference oscillator (LO port)
    if_out : out unsigned(ACC_LOG2 downto 0);  -- dumped window sum, 0..2**ACC_LOG2
    if_stb : out std_logic   -- 1-clk strobe: if_out just updated
  );
end entity het_mixer;

architecture rtl of het_mixer is
  constant WIN_LAST : unsigned(ACC_LOG2 - 1 downto 0) := (others => '1');

  signal mix      : std_logic;
  signal cnt      : unsigned(ACC_LOG2 - 1 downto 0) := (others => '0');
  signal acc      : unsigned(ACC_LOG2 downto 0)     := (others => '0');
  signal if_out_r : unsigned(ACC_LOG2 downto 0)     := (others => '0');
  signal if_stb_r : std_logic := '0';
begin

  mix <= rf_in xor lo_in;  -- the 1-bit multiplier

  accumulate_and_dump : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cnt      <= (others => '0');
        acc      <= (others => '0');
        if_out_r <= (others => '0');
        if_stb_r <= '0';
      else
        if cnt = WIN_LAST then
          -- dump: publish the window sum (including this final clock's
          -- contribution) and restart the accumulator.
          if mix = '1' then
            if_out_r <= acc + 1;
          else
            if_out_r <= acc;
          end if;
          if_stb_r <= '1';
          acc      <= (others => '0');
        else
          if mix = '1' then
            acc <= acc + 1;
          end if;
          if_stb_r <= '0';
        end if;
        cnt <= cnt + 1;  -- wraps naturally mod 2**ACC_LOG2: window cadence
      end if;
    end if;
  end process;

  if_out <= if_out_r;
  if_stb <= if_stb_r;

end architecture rtl;
