-- top.vhd — Phase 1 board top: 440 Hz square wave on a header pin, plus a
-- heartbeat LED proving the bitstream is alive.
--
-- FCW derivation for A440 from a 12 MHz clock, W = 32:
--   fcw = round(440 * 2**32 / 12e6) = 157482  ->  f_out = 439.9996 Hz
--
-- Boards have no reset button, so a small power-on-reset counter holds the
-- NCO in reset for the first 15 clocks after configuration.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
  port (
    clk12     : in  std_logic;  -- 12 MHz board oscillator
    audio_out : out std_logic;  -- square wave: series 1k resistor -> piezo -> GND
    led_hb    : out std_logic   -- heartbeat, ~0.7 Hz
  );
end entity top;

architecture rtl of top is
  constant FCW_A440 : unsigned(31 downto 0) := to_unsigned(157482, 32);

  signal por_cnt : unsigned(3 downto 0)  := (others => '0');
  signal rst     : std_logic;
  signal hb_cnt  : unsigned(23 downto 0) := (others => '0');
  signal phase   : unsigned(31 downto 0);
begin

  rst <= '1' when por_cnt /= x"F" else '0';

  housekeeping : process (clk12)
  begin
    if rising_edge(clk12) then
      if por_cnt /= x"F" then
        por_cnt <= por_cnt + 1;
      end if;
      hb_cnt <= hb_cnt + 1;
    end if;
  end process;

  led_hb <= hb_cnt(23);  -- 12 MHz / 2**24 ~= 0.72 Hz

  u_nco : entity work.nco
    generic map (W => 32)
    port map (
      clk    => clk12,
      rst    => rst,
      en     => '1',
      fcw    => FCW_A440,
      phase  => phase,
      sq_out => audio_out
    );

end architecture rtl;
