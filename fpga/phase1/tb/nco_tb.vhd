-- nco_tb.vhd — self-checking testbench for the NCO.
--
-- Verification approach (DO-254 flavor): every assert is tagged with the
-- requirement it verifies (R1..R3 from rtl/nco.vhd). The frequency check is
-- a *property*, not a golden trace: for any fcw, the number of output rising
-- edges observed over K clocks must satisfy |edges - K*fcw/2**W| <= 1,
-- which follows from the accumulator being exact (error is pure phase
-- truncation, bounded by one wrap). Run with a small W so corner cases are
-- reachable in simulation.
--
-- Sampling note: the TB samples sq_out immediately after rising_edge(clk),
-- i.e. one delta before the DUT's new value propagates — the observed edge
-- sequence is shifted one clock, which the +/-1 tolerance absorbs.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nco_tb is
end entity nco_tb;

architecture sim of nco_tb is
  constant W       : positive := 16;
  constant CLK_PER : time     := 83.333 ns;  -- 12 MHz

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal en    : std_logic := '0';
  signal fcw   : unsigned(W - 1 downto 0) := (others => '0');
  signal phase : unsigned(W - 1 downto 0);
  signal sq    : std_logic;
  signal done  : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.nco
    generic map (W => W)
    port map (
      clk    => clk,
      rst    => rst,
      en     => en,
      fcw    => fcw,
      phase  => phase,
      sq_out => sq
    );

  main : process
    -- R1: count output rising edges over n_clks clocks and compare against
    -- the exact expected count n_clks * fcw / 2**W.
    procedure check_freq(fcw_val : natural; n_clks : positive) is
      variable edges    : natural := 0;
      variable expected : real;
      variable last     : std_logic;
    begin
      rst <= '1'; en <= '0';
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      rst <= '0';
      fcw <= to_unsigned(fcw_val, W);
      en  <= '1';
      wait until rising_edge(clk);
      last := sq;
      for i in 1 to n_clks loop
        wait until rising_edge(clk);
        if sq = '1' and last = '0' then
          edges := edges + 1;
        end if;
        last := sq;
      end loop;
      expected := real(n_clks) * real(fcw_val) / 2.0 ** W;
      assert abs(real(edges) - expected) <= 1.0
        report "R1 FAIL: fcw=" & integer'image(fcw_val) &
               " edges=" & integer'image(edges) &
               " expected=" & real'image(expected)
        severity error;
      report "R1 pass: fcw=" & integer'image(fcw_val) &
             " edges=" & integer'image(edges) &
             " expected~=" & real'image(expected);
    end procedure;

    variable phase_hold : unsigned(W - 1 downto 0);
  begin
    -- R2: synchronous reset clears the phase.
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;  -- let post-edge value settle
    assert phase = 0
      report "R2 FAIL: phase not cleared by synchronous reset"
      severity error;
    report "R2 pass: reset clears phase";

    -- R1 across the operating range, including corners:
    check_freq(700,          20000);       -- arbitrary non-power-of-two
    check_freq(1024,         20000);       -- exact divisor: period = 64 clocks
    check_freq(2 ** (W - 1), 64);          -- Nyquist corner: toggles every clock
    check_freq(1,            3 * 2 ** W);  -- slowest: 3 full wraps -> 3 edges

    -- R3: en='0' freezes the phase.
    en <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    phase_hold := phase;
    for i in 1 to 10 loop
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;
    assert phase = phase_hold
      report "R3 FAIL: phase advanced while en='0'"
      severity error;
    report "R3 pass: clock-enable holds phase";

    report "NCO testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
