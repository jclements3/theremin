-- scale_seq_tb.vhd — self-checking testbench for the scale_seq exercise.
-- Complete: do not modify while doing the exercise; make your RTL pass it.
--
-- Grades requirements R1-R4 from rtl/scale_seq.vhd. Uses a short
-- NOTE_CLKS (96) so two full scale traversals simulate in milliseconds.
-- Expected fcw values are computed here independently with math_real —
-- if your table disagrees with the TB by more than +/-0.5 Hz, R1 fails.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity scale_seq_tb is
end entity scale_seq_tb;

architecture sim of scale_seq_tb is
  constant CLK_HZ    : positive := 12_000_000;
  constant NOTE_CLKS : positive := 96;
  constant CLK_PER   : time     := 83.333 ns;

  type freq_table_t is array (0 to 7) of real;
  constant SCALE_HZ : freq_table_t :=
    (261.6256, 293.6648, 329.6276, 349.2282,
     391.9954, 440.0000, 493.8833, 523.2511);
  constant TOL_HZ : real := 0.5;

  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal en   : std_logic := '0';
  signal fcw  : unsigned(31 downto 0);
  signal idx  : unsigned(2 downto 0);
  signal done : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.scale_seq
    generic map (CLK_HZ => CLK_HZ, NOTE_CLKS => NOTE_CLKS)
    port map (clk => clk, rst => rst, en => en, fcw => fcw, note_idx => idx);

  main : process
    -- R1 frequency identity: is fcw within TOL_HZ of note n?
    procedure check_note(n : natural; tag : string) is
      variable got_hz : real;
    begin
      assert fcw(31 downto 20) = 0
        report tag & " R1 FAIL: fcw wildly out of range (top bits set)"
        severity failure;
      got_hz := real(to_integer(fcw)) * real(CLK_HZ) / 2.0 ** 32;
      assert abs(got_hz - SCALE_HZ(n)) <= TOL_HZ
        report tag & " R1 FAIL: note " & integer'image(n) &
               " got " & real'image(got_hz) & " Hz, expected " &
               real'image(SCALE_HZ(n)) & " Hz"
        severity error;
    end procedure;

    variable expected : natural;  -- unwrapped note counter
    variable cnt      : natural;
    variable idx_hold : natural;
    variable fcw_hold : unsigned(31 downto 0);
  begin
    -- Reset, then enable.
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    en  <= '1';

    -- R3 (initial): starts at note 0 playing C4. Sampled a few clocks in
    -- to allow registered-output pipelines.
    for i in 1 to 3 loop wait until rising_edge(clk); end loop;
    assert to_integer(idx) = 0
      report "R3 FAIL: note_idx /= 0 after reset" severity error;
    check_note(0, "post-reset");

    -- Wait for the first transition away from note 0 (bounded).
    cnt := 0;
    while to_integer(idx) = 0 loop
      wait until rising_edge(clk);
      cnt := cnt + 1;
      assert cnt <= 2 * NOTE_CLKS
        report "R1/R2 FAIL: sequencer never leaves note 0 " &
               "(architecture not implemented yet?)"
        severity failure;
    end loop;

    -- R1 order + R2 duration over two full traversals (16 transitions).
    expected := 1;
    for note in 1 to 16 loop
      assert to_integer(idx) = expected mod 8
        report "R1 FAIL: expected note " & integer'image(expected mod 8) &
               ", got " & integer'image(to_integer(idx))
        severity error;
      cnt := 0;
      while to_integer(idx) = expected mod 8 loop
        wait until rising_edge(clk);
        cnt := cnt + 1;
        if cnt = 3 then
          check_note(expected mod 8, "mid-note");
        end if;
        assert cnt <= NOTE_CLKS + 2
          report "R2 FAIL: note " & integer'image(expected mod 8) &
                 " held longer than NOTE_CLKS"
          severity failure;
      end loop;
      assert cnt = NOTE_CLKS
        report "R2 FAIL: note " & integer'image(expected mod 8) &
               " held " & integer'image(cnt) & " clocks, expected " &
               integer'image(NOTE_CLKS)
        severity error;
      expected := expected + 1;
    end loop;
    report "R1 pass: correct notes in correct order, two full scales";
    report "R2 pass: every note held exactly " &
           integer'image(NOTE_CLKS) & " clocks";

    -- R4: pause mid-note; idx and fcw must freeze.
    for i in 1 to NOTE_CLKS / 4 loop wait until rising_edge(clk); end loop;
    en       <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    idx_hold := to_integer(idx);
    fcw_hold := fcw;
    for i in 1 to 50 loop
      wait until rising_edge(clk);
      assert to_integer(idx) = idx_hold and fcw = fcw_hold
        report "R4 FAIL: outputs changed while en='0'"
        severity error;
    end loop;
    en <= '1';
    report "R4 pass: en='0' freezes the sequencer";

    -- R3 (mid-sequence): reset must return to note 0 / C4.
    for i in 1 to 10 loop wait until rising_edge(clk); end loop;
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    for i in 1 to 3 loop wait until rising_edge(clk); end loop;
    assert to_integer(idx) = 0
      report "R3 FAIL: mid-sequence reset did not return to note 0"
      severity error;
    check_note(0, "post-mid-sequence-reset");
    report "R3 pass: reset returns to note 0 (C4)";

    report "scale_seq testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
