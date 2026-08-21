-- reg_mux_tb.vhd — self-checking testbench for reg_mux.
--
-- Verifies (tags match the header of reg_mux.vhd):
--   R1: the full truth table — all 8 combinations of (sel, a, b) produce
--       q = the selected input one clock later.
--   R2: 1-cycle latency — after an input change, q holds its old value
--       until the next rising edge. A combinational mux fails this check;
--       that is the whole point of the lesson.
--
-- Sampling note: checks wait 1 ns after the clock edge so the DUT's
-- post-edge value has settled (same pattern as fpga/phase1/tb/nco_tb.vhd).

library ieee;
use ieee.std_logic_1164.all;

entity reg_mux_tb is
end entity reg_mux_tb;

architecture sim of reg_mux_tb is
  constant CLK_PER : time := 83.333 ns;  -- 12 MHz, as on the target board

  -- one row of the truth table
  type vec_t is record
    sel, a, b : std_logic;
  end record;
  type vec_arr_t is array (natural range <>) of vec_t;
  constant vecs : vec_arr_t := (
    ('0', '0', '0'), ('0', '0', '1'), ('0', '1', '0'), ('0', '1', '1'),
    ('1', '0', '0'), ('1', '0', '1'), ('1', '1', '0'), ('1', '1', '1'));

  signal clk  : std_logic := '0';
  signal sel  : std_logic := '0';
  signal a    : std_logic := '0';
  signal b    : std_logic := '0';
  signal q    : std_logic;
  signal done : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.reg_mux
    port map (
      clk => clk,
      sel => sel,
      a   => a,
      b   => b,
      q   => q
    );

  main : process
    variable expected : std_logic;
  begin
    -- R1: walk the full truth table.
    for i in vecs'range loop
      sel <= vecs(i).sel;
      a   <= vecs(i).a;
      b   <= vecs(i).b;
      wait until rising_edge(clk);  -- DUT samples the inputs here
      wait for 1 ns;                -- let the post-edge value settle
      if vecs(i).sel = '0' then
        expected := vecs(i).a;
      else
        expected := vecs(i).b;
      end if;
      assert q = expected
        report "R1 FAIL: sel=" & std_logic'image(vecs(i).sel) &
               " a=" & std_logic'image(vecs(i).a) &
               " b=" & std_logic'image(vecs(i).b) &
               " gave q=" & std_logic'image(q)
        severity error;
    end loop;
    report "R1 pass: all 8 (sel,a,b) combinations select the right input";

    -- R2: prove there is a register. Park q at '0', then present inputs
    -- that select '1' and look at q *before* the next clock edge — a
    -- combinational mux would already show '1'.
    sel <= '0'; a <= '0'; b <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert q = '0'
      report "R2 setup FAIL: q should be '0' before the latency check"
      severity error;
    sel <= '1';            -- now selecting b = '1'
    wait for CLK_PER / 4;  -- well inside the cycle, no edge yet
    assert q = '0'
      report "R2 FAIL: q changed without a clock edge (output not registered)"
      severity error;
    wait until rising_edge(clk);
    wait for 1 ns;
    assert q = '1'
      report "R2 FAIL: q did not update on the clock edge"
      severity error;
    report "R2 pass: q changes only on the rising edge (1-cycle latency)";

    report "reg_mux testbench complete: R1-R2 checked (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
