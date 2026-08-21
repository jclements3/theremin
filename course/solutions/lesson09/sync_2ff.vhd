-- sync_2ff.vhd — two-flip-flop synchronizer for a single async input bit.
--
-- Requirements this module implements (verified in sync_2ff_tb.vhd):
--   R1: a level change on async_in appears on sync_out within 2-3 rising
--       clk edges, exactly once — no glitches, no swallowed transitions
--       (for inputs held longer than two clk periods).
--   R2: sync_out changes only at rising clk edges (it is a registered
--       output; nothing combinational touches the async input downstream).
--
-- Why two flip-flops: the first FF samples a signal that can change at any
-- moment relative to clk, so it may go metastable. The second FF gives that
-- metastability a full clock period to resolve before anyone looks. RTL
-- simulation cannot show metastability — here the pair behaves as a plain
-- 2-stage delay — which is exactly why the TB's 3-edge allowance matters:
-- real silicon may need the extra edge.
--
-- No reset on purpose: a synchronizer carries no state worth initializing,
-- and a reset mux in this path only adds delay where margin matters most.
-- (For synthesis you would also pin the pair together with ASYNC_REG-style
-- attributes / a timing exception; that is a constraints topic, not RTL.)
--
-- Radar analog: every real sensor front end is asynchronous to the DSP
-- clock. This module is the border checkpoint the antenna oscillator must
-- pass through before freq_meas may count its edges.

library ieee;
use ieee.std_logic_1164.all;

entity sync_2ff is
  port (
    clk      : in  std_logic;
    async_in : in  std_logic;  -- from another clock domain / the outside world
    sync_out : out std_logic   -- safe to use anywhere in the clk domain
  );
end entity sync_2ff;

architecture rtl of sync_2ff is
  signal meta_ff : std_logic := '0';  -- may go metastable in real hardware
  signal sync_ff : std_logic := '0';  -- resolved, clk-domain-clean copy
begin

  synchronize : process (clk)
  begin
    if rising_edge(clk) then
      meta_ff <= async_in;
      sync_ff <= meta_ff;
    end if;
  end process;

  sync_out <= sync_ff;

end architecture rtl;
