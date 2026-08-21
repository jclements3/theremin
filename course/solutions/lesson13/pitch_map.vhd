-- pitch_map.vhd — period-to-frequency-control-word mapper with clamping and
-- exponential smoothing (the "musicality" block between freq_meas and nco).
--
-- Requirements this module implements (verified in pitch_map_tb.vhd):
--   R1: with period = P_REF, fcw settles to exactly FCW_BASE; synchronous
--       reset also preloads FCW_BASE, so the instrument wakes up on pitch.
--   R2: fcw is strictly monotonically decreasing in period over the
--       unclamped range, following fcw = FCW_BASE + (P_REF - period)*2**SHIFT
--       exactly once smoothing has settled.
--   R3: the mapped value is clamped to [FCW_MIN, FCW_MAX]; an extreme period
--       (hand far away, oscillator glitch) can never push the NCO out of
--       the instrument's range.
--   R4: each valid strobe moves fcw toward the clamped target by
--       delta/2**SMOOTH_SHIFT (never less than 1 LSB), i.e. first-order
--       exponential smoothing at the measurement rate; the step response
--       converges to the target exactly, with no residual offset.
--
-- Signedness: period can exceed P_REF (hand far -> lower antenna frequency
-- -> longer period), so (P_REF - period) is computed in signed arithmetic,
-- CNT_BITS+1 bits wide, then widened to W_CALC bits BEFORE the left shift
-- so no intermediate can overflow. Only after clamping is the result known
-- to be positive and narrowed back to 32-bit unsigned.
--
-- The mapping is LINEAR in period, which is an approximation twice over:
-- true frequency is 1/period, and musical pitch is log-frequency. Over the
-- theremin's narrow period swing the linear map plays fine, and it costs
-- one subtract and one shift instead of a divider. The lesson text owns
-- this approximation explicitly.
--
-- Radar analog: a calibration curve (raw measurement -> engineering units)
-- followed by an alpha filter — the same smoothing a track-while-scan loop
-- uses to trade responsiveness against measurement jitter.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pitch_map is
  generic (
    CNT_BITS : positive := 24;      -- width of the period input (matches freq_meas)
    SHIFT    : natural  := 6;       -- slope: fcw counts per period count = 2**SHIFT
    P_REF    : positive := 3840;    -- period giving FCW_BASE (64 edges of 200 kHz at 12 MHz)
    FCW_BASE : positive := 93640;   -- C4, 261.6256 Hz, for a 32-bit NCO at 12 MHz
    FCW_MIN  : positive := 46820;   -- C3 — one octave below base
    FCW_MAX  : positive := 374561   -- C6 — two octaves above base
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;                        -- synchronous, active-high
    period : in  unsigned(CNT_BITS - 1 downto 0);  -- from freq_meas
    valid  : in  std_logic;                        -- 1-clk strobe qualifying period
    fcw    : out unsigned(31 downto 0)             -- to the NCO
  );
end entity pitch_map;

architecture rtl of pitch_map is
  -- Wide enough for FCW_BASE + (P_REF - period)*2**SHIFT at full input
  -- range: a CNT_BITS+1-bit signed difference shifted left by SHIFT plus a
  -- sign/growth bit — and never narrower than 34 so the 31-bit-max FCW
  -- constants always fit with margin.
  constant W_CALC : positive := maximum(CNT_BITS + 1 + SHIFT + 1, 34);

  -- Smoothing strength: per valid strobe, fcw closes 1/2**SMOOTH_SHIFT of
  -- the remaining distance to the target. At the default integration's
  -- ~3 kHz measurement rate (EDGES=64, 200 kHz oscillator) that is a time
  -- constant of about 2.7 ms — fast enough to feel immediate, slow enough
  -- to bury single-count period jitter.
  constant SMOOTH_SHIFT : natural := 3;

  signal fcw_r : unsigned(31 downto 0) := to_unsigned(FCW_BASE, 32);
begin

  map_and_smooth : process (clk)
    variable diff   : signed(CNT_BITS downto 0);
    variable summed : signed(W_CALC - 1 downto 0);
    variable target : unsigned(31 downto 0);
    variable delta  : signed(32 downto 0);
    variable step   : signed(32 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        fcw_r <= to_unsigned(FCW_BASE, 32);
      elsif valid = '1' then
        -- signed difference: period > P_REF must go negative, not wrap.
        diff   := to_signed(P_REF, CNT_BITS + 1) - signed('0' & period);
        summed := to_signed(FCW_BASE, W_CALC)
                  + shift_left(resize(diff, W_CALC), SHIFT);
        if summed < FCW_MIN then
          target := to_unsigned(FCW_MIN, 32);
        elsif summed > FCW_MAX then
          target := to_unsigned(FCW_MAX, 32);
        else
          target := resize(unsigned(summed), 32);  -- in range, hence non-negative
        end if;
        -- exponential smoothing toward the clamped target. shift_right on
        -- signed rounds toward -inf, so any negative delta still steps by
        -- at least -1; a small positive delta would truncate to 0 and
        -- stall, so nudge it to +1. Both directions therefore land on the
        -- target exactly instead of parking a few LSBs away.
        delta := signed('0' & target) - signed('0' & fcw_r);
        step  := shift_right(delta, SMOOTH_SHIFT);
        if step = 0 and delta > 0 then
          step := to_signed(1, step'length);
        end if;
        fcw_r <= resize(unsigned(signed('0' & fcw_r) + step), 32);
      end if;
    end if;
  end process;

  fcw <= fcw_r;

end architecture rtl;
