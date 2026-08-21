-- sine_lut.vhd — quarter-wave folded sine lookup table (the NCO's waveform memory).
--
-- Requirements this module implements (verified in sine_lut_tb.vhd):
--   R1: peak output amplitude is within 1 LSB of full scale
--       (+/-(2**(DATA_BITS-1) - 1)); the asymmetric most-negative code is
--       never stored, so negating a table entry can never overflow.
--   R2: quarter-wave symmetry is exact — data for phase p equals data for
--       phase 2**(PHASE_BITS-1)-1-p (sin(x) = sin(pi - x)); only
--       2**(PHASE_BITS-2) samples are stored.
--   R3: sign symmetry is exact — data for phase p + 2**(PHASE_BITS-1) is the
--       negation of data for phase p (sin(x + pi) = -sin(x)).
--   R4: output is registered: the sample for a given phase appears exactly
--       one clk edge after that phase is presented. Pure ROM — no reset, no
--       enable, a lookup every clock.
--
-- The table is built at elaboration time by init_rom (ieee.math_real — this
-- is compile-time math, it costs zero gates). Entry i holds
-- round(AMP * sin((i + 0.5) * (pi/2) / Q)). The half-sample offset (+0.5) is
-- what makes R2/R3 *exact*: mirroring an address with "not addr" (== Q-1-addr)
-- lands on the same stored sample, so folding adds zero error. It also means
-- neither 0 nor the exact peak is stored; the largest entry is
-- round(AMP * sin((Q-0.5)/Q * pi/2)), within 1 LSB of full scale (R1).
--
-- Radar analog: this is DDS waveform memory. Table depth sets the
-- phase-truncation spur floor, and quarter-wave folding buys 4x effective
-- depth for two layers of XOR-grade logic — the same trick real DDS chips use.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity sine_lut is
  generic (
    PHASE_BITS : positive := 10;  -- full circle = 2**PHASE_BITS phases (must be >= 3)
    DATA_BITS  : positive := 8    -- signed output width
  );
  port (
    clk   : in  std_logic;
    phase : in  unsigned(PHASE_BITS - 1 downto 0);  -- e.g. top bits of nco's phase port
    data  : out signed(DATA_BITS - 1 downto 0)      -- registered sine sample
  );
end entity sine_lut;

architecture rtl of sine_lut is
  constant Q   : natural := 2 ** (PHASE_BITS - 2);           -- quarter-wave depth
  constant AMP : real    := real(2 ** (DATA_BITS - 1) - 1);  -- full scale (127 for 8 bits)

  type rom_t is array (0 to Q - 1) of signed(DATA_BITS - 1 downto 0);

  function init_rom return rom_t is
    variable r : rom_t;
  begin
    for i in 0 to Q - 1 loop
      r(i) := to_signed(integer(round(
                AMP * sin((real(i) + 0.5) * MATH_PI_OVER_2 / real(Q)))), DATA_BITS);
    end loop;
    return r;
  end function init_rom;

  constant rom : rom_t := init_rom;
begin

  lookup : process (clk)
    variable quad : unsigned(1 downto 0);               -- which quarter of the circle
    variable addr : unsigned(PHASE_BITS - 3 downto 0);  -- index into the quarter table
    variable v    : signed(DATA_BITS - 1 downto 0);
  begin
    if rising_edge(clk) then
      quad := phase(PHASE_BITS - 1 downto PHASE_BITS - 2);
      addr := phase(PHASE_BITS - 3 downto 0);
      if quad(0) = '1' then
        addr := not addr;  -- mirror: Q-1-addr (2nd and 4th quarters run backwards)
      end if;
      v := rom(to_integer(addr));
      if quad(1) = '1' then
        v := -v;           -- lower half of the circle is negative
      end if;
      data <= v;
    end if;
  end process;

end architecture rtl;
