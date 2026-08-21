-- reg_mux.vhd — 2:1 multiplexer with a registered output.
--
-- Requirements this module implements (verified in reg_mux_tb.vhd):
--   R1: q takes the value of a when sel = '0' and b when sel = '1'
--       (the 2:1 mux truth table).
--   R2: the output is registered — q changes only on a rising clock edge,
--       exactly one cycle after the inputs are sampled (1-cycle latency).
--
-- Teaching point: the mux itself is the combinational if/else inside the
-- process; the register is what you get by wrapping that logic in
-- "if rising_edge(clk)". Same expression, different hardware.

library ieee;
use ieee.std_logic_1164.all;

entity reg_mux is
  port (
    clk : in  std_logic;
    sel : in  std_logic;
    a   : in  std_logic;
    b   : in  std_logic;
    q   : out std_logic
  );
end entity reg_mux;

architecture rtl of reg_mux is
begin

  reg : process (clk)
  begin
    if rising_edge(clk) then
      if sel = '0' then
        q <= a;  -- R1
      else
        q <= b;  -- R1
      end if;
    end if;
  end process;

end architecture rtl;
