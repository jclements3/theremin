-- sat_add.vhd — W-bit unsigned adder that saturates instead of wrapping.
--
-- Requirements this module implements (verified in sat_add_tb.vhd):
--   R1: when a + b fits in W bits, sum = a + b and sat = '0'.
--   R2: when a + b overflows W bits, sum clamps to 2**W - 1 (all ones)
--       and sat = '1'.
--   R3: purely combinational — sum and sat follow a and b with no clock.
--
-- Teaching point: resize() both operands to W+1 bits *before* adding, so
-- the carry survives; that carry bit, wide(W), is exactly the saturation
-- flag. A plain W-bit numeric_std add would wrap silently mod 2**W —
-- the testbench demonstrates both behaviors side by side.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sat_add is
  generic (
    W : positive := 8  -- operand width
  );
  port (
    a   : in  unsigned(W - 1 downto 0);
    b   : in  unsigned(W - 1 downto 0);
    sum : out unsigned(W - 1 downto 0);
    sat : out std_logic  -- '1' when the true sum did not fit
  );
end entity sat_add;

architecture rtl of sat_add is
  -- one guard bit: W+1 bits hold any sum of two W-bit numbers exactly
  signal wide : unsigned(W downto 0);
begin

  wide <= resize(a, W + 1) + resize(b, W + 1);

  sum <= (others => '1') when wide(W) = '1' else wide(W - 1 downto 0);  -- R2 / R1
  sat <= wide(W);

end architecture rtl;
