-- het_mixer_tb.vhd — self-checking testbench for the heterodyne mixer.
--
-- Setup: two NCOs (lesson04's nco.vhd, W = 32, 12 MHz clock) drive the RF
-- and LO ports as square waves at ~100.000 kHz and ~100.440 kHz. The
-- difference is ~440 Hz — concert A, made audible by mixing two radio-rate
-- signals neither of which you could hear. Requirement tags (R1, R2 from
-- het_mixer.vhd):
--
--   R1: if_out oscillates at the beat frequency. Measured by hysteresis
--       threshold crossings of the dumped-sample sequence (arm below 1/4
--       scale, fire at 3/4 scale — the beat envelope is a full-scale
--       triangle, so midscale-with-hysteresis is unambiguous). The mean
--       crossing-to-crossing spacing must match the fcw-predicted beat
--       period within 5%.
--   R2: with equal fcw on both NCOs (LO reset released 15 clocks late to
--       give a fixed ~1/8-cycle phase offset), if_out settles to a constant
--       near WIN/4 — spread <= 64 counts, no beat. Zero offset would give a
--       constant too, but a boring all-zero one; the offset shows the mixer
--       acting as a phase detector.
--
-- Timing note: dumps are caught with 'wait until rising_edge(clk) and
-- if_stb = '1''. if_stb is registered and 1 clk wide, so the wait fires on
-- the clock edge AFTER the dump edge, when if_out has been stable for a
-- full cycle — each dump is sampled exactly once.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity het_mixer_tb is
end entity het_mixer_tb;

architecture sim of het_mixer_tb is
  constant W        : positive := 32;         -- NCO phase width
  constant CLK_PER  : time     := 83.333 ns;  -- 12 MHz
  constant ACC_LOG2 : positive := 10;
  constant WIN      : natural  := 2 ** ACC_LOG2;  -- 1024 clks = 85.3 us/dump

  -- fcw = f_out * 2**32 / 12 MHz, rounded to nearest integer.
  constant FCW_RF : natural := 35791394;  -- ~100.000 kHz
  constant FCW_LO : natural := 35948876;  -- ~100.440 kHz
  -- Predicted beat period, in dumps: 2**32 / ((FCW_LO - FCW_RF) * WIN).
  constant BEAT_DUMPS : real :=
    2.0 ** W / (real(FCW_LO - FCW_RF) * real(WIN));

  constant LO_THR : natural := WIN / 4;      -- hysteresis arm level
  constant HI_THR : natural := 3 * WIN / 4;  -- hysteresis fire level

  signal clk     : std_logic := '0';
  signal rst_rf  : std_logic := '1';
  signal rst_lo  : std_logic := '1';
  signal rst_mix : std_logic := '1';
  signal lo_word : unsigned(W - 1 downto 0) := (others => '0');
  signal sq_rf   : std_logic;
  signal sq_lo   : std_logic;
  signal ph_rf   : unsigned(W - 1 downto 0);
  signal ph_lo   : unsigned(W - 1 downto 0);
  signal if_out  : unsigned(ACC_LOG2 downto 0);
  signal if_stb  : std_logic;
  signal done    : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  nco_rf : entity work.nco
    generic map (W => W)
    port map (
      clk    => clk,
      rst    => rst_rf,
      en     => '1',
      fcw    => to_unsigned(FCW_RF, W),
      phase  => ph_rf,
      sq_out => sq_rf
    );

  nco_lo : entity work.nco
    generic map (W => W)
    port map (
      clk    => clk,
      rst    => rst_lo,
      en     => '1',
      fcw    => lo_word,
      phase  => ph_lo,
      sq_out => sq_lo
    );

  dut : entity work.het_mixer
    generic map (ACC_LOG2 => ACC_LOG2)
    port map (
      clk    => clk,
      rst    => rst_mix,
      rf_in  => sq_rf,
      lo_in  => sq_lo,
      if_out => if_out,
      if_stb => if_stb
    );

  main : process
    variable sample   : natural;
    variable armed    : boolean;
    variable n_cross  : natural;
    variable first_x  : natural;
    variable last_x   : natural;
    variable avg_d    : real;
    variable beat_hz  : real;
    variable vmin     : natural;
    variable vmax     : natural;
    variable vsum     : natural;
  begin
    ----------------------------------------------------------------------
    -- R1: offset frequencies -> if_out beats at the difference frequency.
    ----------------------------------------------------------------------
    rst_rf  <= '1';
    rst_lo  <= '1';
    rst_mix <= '1';
    lo_word <= to_unsigned(FCW_LO, W);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst_rf  <= '0';  -- both NCOs start at phase 0: beat envelope starts
    rst_lo  <= '0';  -- at 0 and rises as the phase difference slews.
    rst_mix <= '0';

    armed   := true;
    n_cross := 0;
    first_x := 0;
    last_x  := 0;
    for d in 1 to 280 loop  -- 280 dumps ~ 23.9 ms ~ 10.5 beat periods
      wait until rising_edge(clk) and if_stb = '1';
      sample := to_integer(if_out);
      if armed and sample >= HI_THR then
        if n_cross = 0 then
          first_x := d;
        end if;
        last_x  := d;
        n_cross := n_cross + 1;
        armed   := false;
      elsif (not armed) and sample <= LO_THR then
        armed := true;
      end if;
    end loop;

    assert n_cross >= 3
      report "R1 FAIL: only " & integer'image(n_cross) &
             " threshold crossings; no beat visible"
      severity error;
    avg_d   := real(last_x - first_x) / real(n_cross - 1);
    beat_hz := 1.0 / (avg_d * real(WIN) * 83.333e-9);
    report "R1 measured beat period = " & real'image(avg_d) &
           " dumps = " & real'image(avg_d * real(WIN) * 83.333e-9 * 1000.0) &
           " ms (beat ~= " & real'image(beat_hz) & " Hz, " &
           integer'image(n_cross) & " crossings)";
    assert abs(avg_d - BEAT_DUMPS) <= 0.05 * BEAT_DUMPS
      report "R1 FAIL: measured " & real'image(avg_d) &
             " dumps/beat, expected " & real'image(BEAT_DUMPS) &
             " (tolerance 5%)"
      severity error;
    report "R1 pass: beat period within 5% of expected " &
           real'image(BEAT_DUMPS) & " dumps (440 Hz)";

    ----------------------------------------------------------------------
    -- R2: equal frequencies -> if_out is a constant (phase detector mode).
    ----------------------------------------------------------------------
    rst_rf  <= '1';
    rst_lo  <= '1';
    rst_mix <= '1';
    lo_word <= to_unsigned(FCW_RF, W);  -- LO now equals RF
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst_rf  <= '0';
    rst_mix <= '0';
    for i in 1 to 15 loop  -- hold LO 15 clks: ~1/8 cycle offset at 120
      wait until rising_edge(clk);  -- clks/cycle -> XOR duty ~1/4
    end loop;
    rst_lo <= '0';

    for d in 1 to 2 loop  -- discard dumps straddling the staggered resets
      wait until rising_edge(clk) and if_stb = '1';
    end loop;
    vmin := WIN;
    vmax := 0;
    vsum := 0;
    for d in 1 to 60 loop
      wait until rising_edge(clk) and if_stb = '1';
      sample := to_integer(if_out);
      if sample < vmin then vmin := sample; end if;
      if sample > vmax then vmax := sample; end if;
      vsum := vsum + sample;
    end loop;

    report "R2 dc level = " & integer'image(vsum / 60) &
           " counts (min=" & integer'image(vmin) &
           " max=" & integer'image(vmax) & ", full scale " &
           integer'image(WIN) & ")";
    assert vmax - vmin <= 64
      report "R2 FAIL: if_out spread " & integer'image(vmax - vmin) &
             " counts with equal frequencies; expected a constant"
      severity error;
    report "R2 pass: equal frequencies give constant if_out (no beat), " &
           "spread = " & integer'image(vmax - vmin) & " <= 64 counts";

    report "het_mixer testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
