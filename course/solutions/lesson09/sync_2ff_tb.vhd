-- sync_2ff_tb.vhd — self-checking testbench for the 2-FF synchronizer.
--
-- Verification approach (requirement tags R1..R2 from sync_2ff.vhd):
-- async_in toggles every 599 ns while clk runs at 12 MHz (period
-- 83.333 ns). The half-periods are coprime (83,333 = 167 x 499; 599 is
-- prime) and the stimulus starts at a 100 ns offset, so no async edge ever
-- lands on a clk edge and the async/clk phase alignment sweeps the whole
-- clock period over the run — a deliberate model of two unrelated clocks.
--
--   R1: every async_in transition reaches sync_out within 2-3 rising clk
--       edges, and exactly once — total sync_out transitions must equal
--       total async_in transitions (any glitch or swallowed level breaks
--       the equality).
--   R2: sync_out changes only at rising clk edges (checked at every
--       sync_out event via clk'last_event = 0 ns).
--
-- RTL simulation has no metastability, so the observed R1 latency is
-- always exactly 2 edges; the 3-edge allowance is the hardware truth (the
-- first FF may resolve to the old value and catch up one clock later).

library ieee;
use ieee.std_logic_1164.all;

entity sync_2ff_tb is
end entity sync_2ff_tb;

architecture sim of sync_2ff_tb is
  constant CLK_PER    : time     := 83.333 ns;  -- 12 MHz
  constant ASYNC_HALF : time     := 599 ns;     -- prime-ratio toggle interval
  constant N_TOGGLES  : positive := 120;

  signal clk      : std_logic := '0';
  signal async_in : std_logic := '0';
  signal sync_out : std_logic;
  signal done     : boolean := false;

  signal n_r1_ok : natural := 0;  -- async transitions seen on sync_out in 2-3 edges
  signal n_sync  : natural := 0;  -- total sync_out transitions (glitch detector)
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.sync_2ff
    port map (
      clk      => clk,
      async_in => async_in,
      sync_out => sync_out
    );

  -- R1: after each async_in change, count rising clk edges until sync_out
  -- matches. Must happen within 3 edges and no sooner than 2 (the level
  -- has to traverse both flops). The 599 ns level time (> 7 clk periods)
  -- guarantees this process is back waiting before the next change.
  check_r1 : process
    variable target  : std_logic;
    variable settled : boolean;
  begin
    wait on async_in;
    target  := async_in;
    settled := false;
    for e in 1 to 3 loop
      wait until rising_edge(clk);
      wait for 1 ns;  -- let the post-edge value settle before sampling
      if sync_out = target then
        assert e >= 2
          report "R1 FAIL: sync_out changed after only " &
                 integer'image(e) & " clk edge(s) - bypassing a flop?"
          severity error;
        settled := true;
        exit;
      end if;
    end loop;
    assert settled
      report "R1 FAIL: async_in change at " & time'image(async_in'last_event) &
             " before now not on sync_out within 3 clk edges"
      severity error;
    if settled then
      n_r1_ok <= n_r1_ok + 1;
    end if;
  end process;

  -- R2: every sync_out event must coincide with a rising clk edge (the
  -- time-0 'U' -> '0' initialization event is not a transition; skip it).
  check_r2 : process
  begin
    wait on sync_out;
    if now > 0 ns then
      assert clk = '1' and clk'last_event = 0 ns
        report "R2 FAIL: sync_out changed at " & time'image(now) &
               ", not aligned with a rising clk edge"
        severity error;
      n_sync <= n_sync + 1;
    end if;
  end process;

  main : process
  begin
    wait for 100 ns;  -- offset so async edges never coincide with clk edges
    for i in 1 to N_TOGGLES loop
      async_in <= not async_in;
      wait for ASYNC_HALF;
    end loop;
    wait for 4 * CLK_PER;  -- flush the last transition through both flops

    assert n_r1_ok = N_TOGGLES
      report "R1 FAIL: only " & integer'image(n_r1_ok) & " of " &
             integer'image(N_TOGGLES) & " transitions arrived in 2-3 edges"
      severity error;
    report "R1 pass: " & integer'image(n_r1_ok) & "/" &
           integer'image(N_TOGGLES) &
           " async transitions reached sync_out in 2-3 clk edges";

    assert n_sync = N_TOGGLES
      report "R1 FAIL: " & integer'image(n_sync) &
             " sync_out transitions for " & integer'image(N_TOGGLES) &
             " async transitions - glitch or swallowed level"
      severity error;
    report "R1 pass: no glitches - sync_out transition count matches async_in (" &
           integer'image(n_sync) & ")";

    report "R2 pass: all " & integer'image(n_sync) &
           " sync_out transitions occurred on rising clk edges";

    report "sync_2ff testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
