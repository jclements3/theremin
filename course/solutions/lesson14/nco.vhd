-- nco.vhd — Numerically controlled oscillator (phase accumulator DDS core).
--
-- Requirements this module implements (verified in tb/nco_tb.vhd):
--   R1: average output frequency f_out = fcw * f_clk / 2**W, with per-edge
--       timing jitter bounded by one clock period (inherent to a truncated
--       phase accumulator).
--   R2: synchronous active-high reset clears the phase accumulator to zero.
--   R3: when en = '0' the phase holds (clock-enable style; no gated clocks).
--
-- Radar analog: this is a DDS / stable local oscillator (STALO). The
-- frequency resolution f_clk / 2**W is the same quantity that sets chirp
-- step granularity in an FMCW waveform generator. The 'phase' output port
-- is the future address bus for a sine LUT (Phase 4) and the phase input
-- to a quadrature mixer (Phase 5).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nco is
  generic (
    W : positive := 32  -- phase accumulator width
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;                 -- synchronous, active-high
    en     : in  std_logic;                 -- clock enable
    fcw    : in  unsigned(W - 1 downto 0);  -- frequency control word
    phase  : out unsigned(W - 1 downto 0);  -- current phase (test point / LUT address)
    sq_out : out std_logic                  -- MSB of phase: square wave at f_out
  );
end entity nco;

architecture rtl of nco is
  signal acc : unsigned(W - 1 downto 0) := (others => '0');
begin

  accumulate : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        acc <= (others => '0');
      elsif en = '1' then
        acc <= acc + fcw;  -- wraps naturally mod 2**W: one full wrap = one output cycle
      end if;
    end if;
  end process;

  phase  <= acc;
  sq_out <= acc(W - 1);

end architecture rtl;
