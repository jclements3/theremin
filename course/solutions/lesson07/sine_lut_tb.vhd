-- sine_lut_tb.vhd — self-checking testbench for sine_lut.
--
-- Verification approach: sweep the full phase circle once, capturing the
-- registered output for every phase into an array, then check *properties*
-- of that array — no golden trace. Every assert is tagged with the
-- requirement it verifies (R1..R4 from sine_lut.vhd):
--   R1: peak amplitude within 1 LSB of full scale, both polarities.
--   R2: quarter symmetry — samples(p) = samples(HALF-1-p) exactly.
--   R3: sign symmetry — samples(p+HALF) = -samples(p) exactly.
--   R4: exactly one clock of latency: output holds mid-cycle after a phase
--       change (not combinational) and updates on the next edge (not slower).
--
-- Sampling note: phase is applied just after an edge, so the *next* rising
-- edge registers it; the TB waits 1 ns past that edge before reading data.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sine_lut_tb is
end entity sine_lut_tb;

architecture sim of sine_lut_tb is
  constant PB      : positive := 10;             -- PHASE_BITS under test
  constant DB      : positive := 8;              -- DATA_BITS under test
  constant N       : natural  := 2 ** PB;        -- phases in a full circle
  constant HALF    : natural  := N / 2;
  constant FS      : integer  := 2 ** (DB - 1) - 1;  -- full scale = 127
  constant CLK_PER : time     := 83.333 ns;      -- 12 MHz

  signal clk   : std_logic := '0';
  signal phase : unsigned(PB - 1 downto 0) := (others => '0');
  signal data  : signed(DB - 1 downto 0);
  signal done  : boolean := false;

  type sample_arr is array (0 to N - 1) of integer;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.sine_lut
    generic map (PHASE_BITS => PB, DATA_BITS => DB)
    port map (clk => clk, phase => phase, data => data);

  main : process
    variable samples    : sample_arr;
    variable vmax, vmin : integer;
    variable errs       : natural;
  begin
    -- one full circle: apply phase i, let the next edge register it, read.
    for i in 0 to N - 1 loop
      phase <= to_unsigned(i, PB);
      wait until rising_edge(clk);  -- DUT registers the sample for phase i
      wait for 1 ns;                -- let data settle past the edge
      samples(i) := to_integer(data);
    end loop;

    -- R1: peak amplitude within 1 LSB of full scale, both polarities.
    vmax := integer'low;
    vmin := integer'high;
    for i in 0 to N - 1 loop
      if samples(i) > vmax then vmax := samples(i); end if;
      if samples(i) < vmin then vmin := samples(i); end if;
    end loop;
    assert vmax <= FS and vmax >= FS - 1
      report "R1 FAIL: positive peak " & integer'image(vmax) &
             " not within 1 LSB of full scale " & integer'image(FS)
      severity error;
    assert vmin >= -FS and vmin <= -(FS - 1)
      report "R1 FAIL: negative peak " & integer'image(vmin) &
             " not within 1 LSB of full scale " & integer'image(-FS)
      severity error;
    report "R1 pass: peaks " & integer'image(vmax) & " / " &
           integer'image(vmin) & " within 1 LSB of full scale " &
           integer'image(FS);

    -- R2: quarter symmetry, sin(x) = sin(pi - x), exact.
    errs := 0;
    for i in 0 to HALF - 1 loop
      if samples(i) /= samples(HALF - 1 - i) then
        errs := errs + 1;
      end if;
    end loop;
    assert errs = 0
      report "R2 FAIL: " & integer'image(errs) &
             " phases break sin(x) = sin(pi - x)"
      severity error;
    report "R2 pass: quarter symmetry exact over " &
           integer'image(HALF) & " phases";

    -- R3: sign symmetry, sin(x + pi) = -sin(x), exact.
    errs := 0;
    for i in 0 to HALF - 1 loop
      if samples(i + HALF) /= -samples(i) then
        errs := errs + 1;
      end if;
    end loop;
    assert errs = 0
      report "R3 FAIL: " & integer'image(errs) &
             " phases break sin(x + pi) = -sin(x)"
      severity error;
    report "R3 pass: sign symmetry exact over " &
           integer'image(HALF) & " phases";

    -- R4: exactly one clock of latency. Settle at phase 0, then step to the
    -- positive peak (N/4): the output must NOT change before the next edge
    -- and MUST have changed just after it.
    phase <= to_unsigned(0, PB);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;
    assert to_integer(data) = samples(0)
      report "R4 FAIL: output for phase 0 not stable before the step"
      severity error;
    phase <= to_unsigned(N / 4, PB);
    wait for CLK_PER / 4;  -- mid-cycle, before the registering edge
    assert to_integer(data) = samples(0)
      report "R4 FAIL: output changed before the clock edge (combinational?)"
      severity error;
    wait until rising_edge(clk);
    wait for 1 ns;
    assert to_integer(data) = samples(N / 4)
      report "R4 FAIL: output did not update one edge after the phase change"
      severity error;
    report "R4 pass: registered output, exactly one clock of latency";

    report "sine_lut testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
