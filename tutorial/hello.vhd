-- hello.vhd — smallest possible GHDL sanity check.
-- A testbench needs no ports and no logic; this one just proves the
-- analyze -> elaborate -> run pipeline (including the glibc shim link)
-- works, and shows what a passing assert looks like.

entity hello_tb is
end entity hello_tb;

architecture sim of hello_tb is
begin

  main : process
  begin
    report "Hello, world - GHDL simulation is alive.";
    assert 2 + 2 = 4
      report "arithmetic is broken; seek shelter"
      severity failure;
    report "hello_tb complete: 1 check passed.";
    wait;  -- a testbench process must end in a wait or it loops forever
  end process;

end architecture sim;
