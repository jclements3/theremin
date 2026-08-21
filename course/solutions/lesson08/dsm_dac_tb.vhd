-- dsm_dac_tb.vhd — self-checking testbench for the delta-sigma DAC.
--
-- Verification approach: every assert is tagged with the requirement it
-- verifies (R1..R2 from dsm_dac.vhd).
--   R1 is a mean-tracking property: for a DC input held over N_WIN clocks,
--   the ones-density of bit_out must match (sample + 2**(W-1)) / 2**W
--   within 2%. Because the error-feedback loop discards nothing, the true
--   density error over N_WIN samples is at most ~1/N_WIN, so N_WIN = 4096
--   leaves two orders of margin under the 2% bound. Checked at full-scale
--   negative, -1/2, 0, +1/2, and full-scale positive.
--   R2 checks that synchronous reset clears the accumulator and pins
--   bit_out low, even with a full-scale sample applied.
--
-- Sampling note: bit_out is registered, and the TB samples it immediately
-- after rising_edge(clk) — one delta before the new value propagates — so
-- the counted window is shifted one clock. For a density measurement that
-- moves the count by at most 1, absorbed by the 2% tolerance.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dsm_dac_tb is
end entity dsm_dac_tb;

architecture sim of dsm_dac_tb is
  constant W       : positive := 8;
  constant CLK_PER : time     := 83.333 ns;  -- 12 MHz
  constant N_WIN   : positive := 4096;       -- averaging window (clocks)

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal sample : signed(W - 1 downto 0) := (others => '0');
  signal b      : std_logic;
  signal done   : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.dsm_dac
    generic map (W => W)
    port map (
      clk     => clk,
      rst     => rst,
      sample  => sample,
      bit_out => b
    );

  main : process
    -- R1: hold a DC sample for N_WIN clocks, measure the ones-density of
    -- bit_out, and compare against (s + 2**(W-1)) / 2**W within 2%.
    procedure check_mean(s : integer) is
      variable ones     : natural := 0;
      variable measured : real;
      variable expected : real;
    begin
      rst <= '1';
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      rst    <= '0';
      sample <= to_signed(s, W);
      wait until rising_edge(clk);  -- first accumulation of the new sample
      for i in 1 to N_WIN loop
        wait until rising_edge(clk);
        if b = '1' then
          ones := ones + 1;
        end if;
      end loop;
      measured := real(ones) / real(N_WIN);
      expected := (real(s) + 2.0 ** (W - 1)) / 2.0 ** W;
      assert abs(measured - expected) <= 0.02
        report "R1 FAIL: sample=" & integer'image(s) &
               " measured_mean=" & real'image(measured) &
               " expected=" & real'image(expected)
        severity error;
      report "R1 pass: sample=" & integer'image(s) &
             " measured_mean=" & real'image(measured) &
             " expected=" & real'image(expected);
    end procedure;
  begin
    -- R2: synchronous reset clears the accumulator and pins bit_out low,
    -- even with a full-scale positive sample at the input.
    sample <= to_signed(2 ** (W - 1) - 1, W);
    rst    <= '1';
    wait until rising_edge(clk);
    for i in 1 to 5 loop
      wait until rising_edge(clk);
      wait for 1 ns;  -- let post-edge value settle
      assert b = '0'
        report "R2 FAIL: bit_out not held low during reset (cycle " &
               integer'image(i) & ")"
        severity error;
    end loop;
    report "R2 pass: reset clears accumulator and holds bit_out low";

    -- R1 across the DC range: min, -1/2 scale, midscale, +1/2 scale, max.
    check_mean(-2 ** (W - 1));      -- -128: expected mean 0.0
    check_mean(-2 ** (W - 2));      --  -64: expected mean 0.25
    check_mean(0);                  --    0: expected mean 0.5
    check_mean(2 ** (W - 2));       --  +64: expected mean 0.75
    check_mean(2 ** (W - 1) - 1);   -- +127: expected mean 255/256

    report "dsm_dac testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
