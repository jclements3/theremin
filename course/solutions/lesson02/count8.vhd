-- count8.vhd — 8-bit wrapping up-counter with clock enable.
--
-- Requirements this module implements (verified in count8_tb.vhd):
--   R1: with en = '1', count increments by exactly 1 each rising clock edge.
--   R2: the counter wraps: 255 -> 0 (natural mod-2**8 unsigned arithmetic).
--   R3: en = '0' holds the count (clock enable, never a gated clock).
--   R4: synchronous active-high reset clears the count to zero, and wins
--       over en when both are asserted.
--
-- Teaching point: "cnt + 1" on an unsigned wraps silently — here that is
-- the feature, not a bug. The priority order rst > en inside one clocked
-- process is the house pattern for every sequential block in this course.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity count8 is
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;  -- synchronous, active-high
    en    : in  std_logic;  -- clock enable
    count : out unsigned(7 downto 0)
  );
end entity count8;

architecture rtl of count8 is
  signal cnt : unsigned(7 downto 0) := (others => '0');
begin

  advance : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cnt <= (others => '0');  -- R4
      elsif en = '1' then
        cnt <= cnt + 1;          -- R1; wraps 255 -> 0 (R2)
      end if;                    -- else: hold (R3)
    end if;
  end process;

  count <= cnt;

end architecture rtl;
