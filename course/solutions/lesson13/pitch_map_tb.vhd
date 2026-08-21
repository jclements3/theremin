-- pitch_map_tb.vhd — self-checking testbench for pitch_map.
--
-- Verification approach: every assert is tagged with the requirement it
-- verifies (R1..R4 from pitch_map.vhd). Expected values are recomputed in
-- the TB with plain integer math (the map is exactly linear-then-clamped),
-- so the checks are exact equalities, not tolerances — the smoothing
-- converges to the target with zero residual, and we hold each period long
-- enough (many valid strobes) for it to get there.
--
-- Two DUT instances: `dut` uses the pinned generic defaults throughout.
-- With those defaults the FCW_MAX clamp is unreachable — the steepest
-- physical case (period = 1) maps to 339336, still below FCW_MAX = 374561;
-- the top clamp is headroom, not an active limit. To prove the clamp logic
-- itself, `dut_hi` overrides only SHIFT (6 -> 8), steepening the slope so
-- period = 1 maps far above FCW_MAX. Both instances share all stimulus.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pitch_map_tb is
end entity pitch_map_tb;

architecture sim of pitch_map_tb is
  -- pinned generic defaults, restated for the TB's own expected-value math
  constant CNT_BITS : positive := 24;
  constant SHIFT    : natural  := 6;
  constant P_REF    : positive := 3840;
  constant FCW_BASE : positive := 93640;
  constant FCW_MIN  : positive := 46820;
  constant FCW_MAX  : positive := 374561;
  constant SHIFT_HI : natural  := 8;  -- dut_hi only: makes FCW_MAX reachable

  constant CLK_PER : time := 83.333 ns;  -- 12 MHz

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal period : unsigned(CNT_BITS - 1 downto 0) := (others => '0');
  signal valid  : std_logic := '0';
  signal fcw    : unsigned(31 downto 0);
  signal fcw_hi : unsigned(31 downto 0);
  signal done   : boolean := false;

  -- the ideal map: linear in period, then clamped. Callers keep
  -- period_val small enough that the integer math cannot overflow.
  function expected(period_val : natural; shift_val : natural) return natural is
    variable t : integer;
  begin
    t := FCW_BASE + (P_REF - period_val) * 2 ** shift_val;
    if t < FCW_MIN then
      t := FCW_MIN;
    end if;
    if t > FCW_MAX then
      t := FCW_MAX;
    end if;
    return t;
  end function;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.pitch_map  -- pinned defaults, as theremin_top will use
    port map (
      clk    => clk,
      rst    => rst,
      period => period,
      valid  => valid,
      fcw    => fcw
    );

  dut_hi : entity work.pitch_map  -- steeper slope: exercises the FCW_MAX clamp
    generic map (SHIFT => SHIFT_HI)
    port map (
      clk    => clk,
      rst    => rst,
      period => period,
      valid  => valid,
      fcw    => fcw_hi
    );

  main : process
    -- one measurement: valid high for 1 clk, then a 3-clk gap, mimicking
    -- freq_meas strobes (spread out, never back-to-back).
    procedure pulse_valid(n : positive) is
    begin
      for i in 1 to n loop
        valid <= '1';
        wait until rising_edge(clk);
        valid <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;  -- let the last post-edge value settle
    end procedure;

    -- apply a period and give the smoothing n measurements to converge
    procedure settle(period_val : natural; n : positive) is
    begin
      period <= to_unsigned(period_val, CNT_BITS);
      wait until rising_edge(clk);
      pulse_valid(n);
    end procedure;

    variable prev_fcw : natural;
    variable exp_fcw  : natural;
    variable steps    : natural;
  begin
    -- ------------------------------------------------------------------
    -- R1: period = P_REF -> fcw = FCW_BASE (reset preload and settled).
    -- ------------------------------------------------------------------
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;
    assert fcw = FCW_BASE
      report "R1 FAIL: reset did not preload fcw with FCW_BASE"
      severity error;
    rst <= '0';
    settle(P_REF, 8);
    assert fcw = FCW_BASE
      report "R1 FAIL: period=P_REF gave fcw=" & integer'image(to_integer(fcw)) &
             " expected FCW_BASE=" & integer'image(FCW_BASE)
      severity error;
    report "R1 pass: reset preloads FCW_BASE and period=" & integer'image(P_REF) &
           " holds fcw=" & integer'image(FCW_BASE);

    -- ------------------------------------------------------------------
    -- R2: strictly decreasing fcw for increasing period, exact linear
    -- law, across an unclamped sweep straddling P_REF.
    -- ------------------------------------------------------------------
    prev_fcw := natural'high;
    for p in 16 to 22 loop  -- periods 3200, 3400, ... 4400
      settle(p * 200, 150);
      exp_fcw := expected(p * 200, SHIFT);
      assert to_integer(fcw) = exp_fcw
        report "R2 FAIL: period=" & integer'image(p * 200) &
               " fcw=" & integer'image(to_integer(fcw)) &
               " expected=" & integer'image(exp_fcw)
        severity error;
      assert to_integer(fcw) < prev_fcw
        report "R2 FAIL: fcw not strictly decreasing at period=" &
               integer'image(p * 200)
        severity error;
      report "R2 pass: period=" & integer'image(p * 200) &
             " fcw=" & integer'image(to_integer(fcw)) & " (exact, decreasing)";
      prev_fcw := to_integer(fcw);
    end loop;

    -- ------------------------------------------------------------------
    -- R3: clamping. A huge period (hand far / glitch) pins the default
    -- instance at FCW_MIN; the arithmetic survives period >> P_REF because
    -- the difference is signed. The steep dut_hi instance proves FCW_MAX.
    -- ------------------------------------------------------------------
    settle(2 ** CNT_BITS - 1, 250);
    assert fcw = FCW_MIN
      report "R3 FAIL: extreme period gave fcw=" & integer'image(to_integer(fcw)) &
             " expected clamp FCW_MIN=" & integer'image(FCW_MIN)
      severity error;
    report "R3 pass: period=" & integer'image(2 ** CNT_BITS - 1) &
           " clamps fcw at FCW_MIN=" & integer'image(FCW_MIN);

    settle(1, 250);
    exp_fcw := expected(1, SHIFT);  -- 339336: below FCW_MAX, top clamp is headroom
    assert to_integer(fcw) = exp_fcw
      report "R3 FAIL: period=1 gave fcw=" & integer'image(to_integer(fcw)) &
             " expected unclamped " & integer'image(exp_fcw)
      severity error;
    assert fcw_hi = FCW_MAX
      report "R3 FAIL: period=1 at SHIFT=8 gave fcw=" &
             integer'image(to_integer(fcw_hi)) &
             " expected clamp FCW_MAX=" & integer'image(FCW_MAX)
      severity error;
    report "R3 pass: period=1 stays unclamped at default slope (fcw=" &
           integer'image(exp_fcw) & "), clamps at FCW_MAX=" &
           integer'image(FCW_MAX) & " with SHIFT=" & integer'image(SHIFT_HI);

    -- ------------------------------------------------------------------
    -- R4: smoothing step response. From a settled FCW_BASE, step the
    -- period; the first measurement must move fcw only part way (proof of
    -- smoothing), then the trajectory must be monotonic and converge to
    -- the new target exactly.
    -- ------------------------------------------------------------------
    settle(P_REF, 250);
    exp_fcw := expected(P_REF + 200, SHIFT);  -- step target: 80840
    settle(P_REF + 200, 1);                   -- exactly one measurement
    assert to_integer(fcw) < FCW_BASE and to_integer(fcw) > exp_fcw
      report "R4 FAIL: first measurement after step gave fcw=" &
             integer'image(to_integer(fcw)) &
             " (expected strictly between " & integer'image(exp_fcw) &
             " and " & integer'image(FCW_BASE) & ")"
      severity error;
    prev_fcw := to_integer(fcw);
    steps    := 1;
    while to_integer(fcw) /= exp_fcw and steps < 200 loop
      pulse_valid(1);
      steps := steps + 1;
      assert to_integer(fcw) <= prev_fcw and to_integer(fcw) >= exp_fcw
        report "R4 FAIL: non-monotonic step response, fcw=" &
               integer'image(to_integer(fcw)) & " after " &
               integer'image(steps) & " measurements"
        severity error;
      prev_fcw := to_integer(fcw);
    end loop;
    assert to_integer(fcw) = exp_fcw
      report "R4 FAIL: did not converge to " & integer'image(exp_fcw) &
             " within 200 measurements (fcw=" &
             integer'image(to_integer(fcw)) & ")"
      severity error;
    report "R4 pass: step to period=" & integer'image(P_REF + 200) &
           " converged exactly to fcw=" & integer'image(exp_fcw) &
           " in " & integer'image(steps) &
           " measurements, first step partial";

    report "pitch_map testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
