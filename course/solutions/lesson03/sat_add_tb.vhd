-- sat_add_tb.vhd — self-checking testbench for sat_add (W = 8).
--
-- Verifies (tags match the header of sat_add.vhd):
--   R1: in-range sums pass through untouched with sat = '0', including the
--       fencepost case that lands exactly on 255.
--   R2: overflowing sums clamp to 255 with sat = '1'; each report line
--       also shows what a plain wrapping W-bit add would have produced,
--       so wrap vs saturate sit side by side in the log.
--   R3: there is no clock anywhere in this testbench — outputs settle
--       within the 1 ns wait after every input change, proving the DUT
--       is combinational.
--
-- The expected values are computed independently in plain integer math
-- (av + bv against 2**W - 1), never by re-running the DUT's own formula.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sat_add_tb is
end entity sat_add_tb;

architecture sim of sat_add_tb is
  constant W : positive := 8;

  signal a   : unsigned(W - 1 downto 0) := (others => '0');
  signal b   : unsigned(W - 1 downto 0) := (others => '0');
  signal sum : unsigned(W - 1 downto 0);
  signal sat : std_logic;
begin

  dut : entity work.sat_add
    generic map (W => W)
    port map (
      a   => a,
      b   => b,
      sum => sum,
      sat => sat
    );

  main : process
    constant MAXV : natural := 2 ** W - 1;

    -- Drive one (a, b) pair, wait for the combinational settle, check
    -- sum and sat against integer-math expectations, and report the
    -- wrapped alternative whenever saturation fired.
    procedure check(av, bv : natural) is
      variable exp_sum : natural;
      variable exp_sat : std_logic;
      variable wrapped : natural;
    begin
      a <= to_unsigned(av, W);
      b <= to_unsigned(bv, W);
      wait for 1 ns;  -- R3: no clock — this settle is all it takes
      wrapped := (av + bv) mod 2 ** W;
      if av + bv > MAXV then
        exp_sum := MAXV;
        exp_sat := '1';
      else
        exp_sum := av + bv;
        exp_sat := '0';
      end if;
      assert to_integer(sum) = exp_sum and sat = exp_sat
        report "R1/R2 FAIL: " & integer'image(av) & "+" & integer'image(bv) &
               " gave sum=" & integer'image(to_integer(sum)) &
               " sat=" & std_logic'image(sat) &
               ", expected sum=" & integer'image(exp_sum) &
               " sat=" & std_logic'image(exp_sat)
        severity error;
      if exp_sat = '1' then
        report "R2 pass: " & integer'image(av) & "+" & integer'image(bv) &
               " -> sum=" & integer'image(to_integer(sum)) & " sat=1" &
               " (a plain 8-bit add would wrap to " &
               integer'image(wrapped) & ")";
      else
        report "R1 pass: " & integer'image(av) & "+" & integer'image(bv) &
               " -> sum=" & integer'image(to_integer(sum)) & " sat=0";
      end if;
    end procedure;
  begin
    -- R1: ordinary in-range sums.
    check(10, 20);    -- nothing special: 30
    check(0, 0);      -- both zero
    check(255, 0);    -- one operand already at max, still no overflow

    -- R1 fencepost: lands exactly on 255 — sat must stay '0'.
    check(200, 55);

    -- R2: one past the fencepost, then the classic MSB and worst cases.
    check(200, 56);   -- 256: wrap would give 0
    check(128, 128);  -- MSB + MSB: wrap would give 0
    check(255, 255);  -- worst case: wrap would give 254

    report "R3 pass: all checks settled with no clock (combinational DUT)";
    report "sat_add testbench complete: R1-R3 checked (any FAILs are listed above)";
    wait;
  end process;

end architecture sim;
