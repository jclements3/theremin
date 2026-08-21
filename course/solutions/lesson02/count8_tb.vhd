-- count8_tb.vhd — self-checking testbench for count8.
--
-- Verifies (tags match the header of count8.vhd):
--   R1: count follows 1, 2, ..., 10 — one increment per enabled clock.
--   R2: the 255 -> 0 wrap (reached by actually counting there, so the
--       whole sequence is exercised, not just the corner).
--   R3: en = '0' freezes the count.
--   R4: synchronous reset clears the count, including mid-count with
--       en still asserted (reset priority).
--
-- Sampling note: checks wait 1 ns after the clock edge so the DUT's
-- post-edge value has settled (same pattern as fpga/phase1/tb/nco_tb.vhd).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity count8_tb is
end entity count8_tb;

architecture sim of count8_tb is
  constant CLK_PER : time := 83.333 ns;  -- 12 MHz, as on the target board

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal en    : std_logic := '0';
  signal count : unsigned(7 downto 0);
  signal done  : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.count8
    port map (
      clk   => clk,
      rst   => rst,
      en    => en,
      count => count
    );

  main : process
    variable hold : unsigned(7 downto 0);
  begin
    -- R4: synchronous reset clears the count.
    rst <= '1'; en <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;
    assert count = 0
      report "R4 FAIL: count not cleared by synchronous reset"
      severity error;
    report "R4 pass: synchronous reset clears count to 0";
    rst <= '0';

    -- R1: exactly one increment per enabled clock.
    en <= '1';
    for i in 1 to 10 loop
      wait until rising_edge(clk);
      wait for 1 ns;
      assert count = i
        report "R1 FAIL: after " & integer'image(i) &
               " enabled clocks, count=" & integer'image(to_integer(count))
        severity error;
    end loop;
    report "R1 pass: count follows 1,2,...,10 - one increment per enabled clock";

    -- R3: en='0' freezes the count.
    en <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    hold := count;
    for i in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;
    assert count = hold
      report "R3 FAIL: count advanced while en='0'"
      severity error;
    report "R3 pass: en='0' holds count at " & integer'image(to_integer(hold));

    -- R2: count the rest of the way to 255, then one more clock wraps to 0.
    en <= '1';
    for i in 1 to 245 loop  -- 10 held + 245 more = 255
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;
    assert count = 255
      report "R2 setup FAIL: expected count=255, got " &
             integer'image(to_integer(count))
      severity error;
    wait until rising_edge(clk);
    wait for 1 ns;
    assert count = 0
      report "R2 FAIL: 255 + 1 should wrap to 0, got " &
             integer'image(to_integer(count))
      severity error;
    report "R2 pass: 255 -> 0 wrap (mod-256 arithmetic)";

    -- R4 again: reset must win over enable mid-count.
    for i in 1 to 3 loop  -- count = 3
      wait until rising_edge(clk);
    end loop;
    rst <= '1';  -- en is still '1' — reset has priority
    wait until rising_edge(clk);
    wait for 1 ns;
    assert count = 0
      report "R4 FAIL: reset did not override enable"
      severity error;
    report "R4 pass: reset overrides enable mid-count";
    rst <= '0';

    report "count8 testbench complete: R1-R4 checked (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
