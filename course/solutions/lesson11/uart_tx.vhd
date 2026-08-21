-- uart_tx.vhd — 8N1 UART transmitter (telemetry link, lesson 11).
--
-- Requirements this module implements (verified in uart_tx_tb.vhd):
--   R1: 8N1 framing — each frame on txd is one low start bit, 8 data bits
--       lsb-first, one high stop bit, every bit lasting DIV = CLK_HZ/BAUD
--       clock cycles.
--   R2: the 8 data bits of the frame equal the byte on 'data' at the clock
--       edge where 'stb' was accepted.
--   R3: busy/strobe handshake — busy rises the cycle stb is accepted, stays
--       high through the stop bit, and stb is IGNORED while busy (no queue:
--       the in-flight payload is untouched and no second frame follows).
--   R4: txd idles high — out of reset and between frames.
--
-- Baud division: DIV = CLK_HZ / BAUD, integer truncation. At the defaults
-- 12_000_000 / 115_200 = 104 (exact quotient 104.17), so the line runs
-- 0.16 % fast — far inside the ~2 % per-frame budget an 8N1 receiver
-- tolerates, since the receiver re-synchronizes on every start edge.
--
-- Structure: a single 10-bit shift register holds the whole frame
-- ('1' stop & data & '0' start). txd is just shreg(0), so the line is
-- driven by a register at all times; idle is maintained by shifting in '1's.
-- bits_left doubles as the state: 0 = idle, nonzero = sending.
--
-- Radar analog: the instrumentation link. Every radar testbed streams
-- housekeeping (AGC state, detections, temperatures) over exactly this
-- kind of low-rate serial sideband; the busy/stb handshake is the same
-- backpressure contract you meet again in AXI-Stream's valid/ready.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
  generic (
    CLK_HZ : positive := 12_000_000;
    BAUD   : positive := 115_200
  );
  port (
    clk  : in  std_logic;
    rst  : in  std_logic;                     -- synchronous, active-high
    data : in  std_logic_vector(7 downto 0);  -- byte to send, latched on accept
    stb  : in  std_logic;                     -- request: send 'data' (1 clk)
    busy : out std_logic;                     -- '1' while a frame is on the wire
    txd  : out std_logic                      -- serial line, idles '1'
  );
end entity uart_tx;

architecture rtl of uart_tx is
  constant DIV : positive := CLK_HZ / BAUD;  -- clocks per bit

  -- frame shift register: (9)=stop, (8:1)=data msb..lsb, (0)=start.
  -- txd = shreg(0); shifting right emits start, d0..d7, stop in order.
  signal shreg     : std_logic_vector(9 downto 0) := (others => '1');
  signal bits_left : natural range 0 to 10 := 0;
  signal baud_cnt  : natural range 0 to DIV - 1 := 0;
begin

  txd  <= shreg(0);
  busy <= '1' when bits_left /= 0 else '0';

  shift : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        shreg     <= (others => '1');  -- line high: idle (R4)
        bits_left <= 0;
        baud_cnt  <= 0;
      elsif bits_left = 0 then
        -- idle: only here is stb honored (R3)
        if stb = '1' then
          shreg     <= '1' & data & '0';  -- stop & payload & start (R1, R2)
          bits_left <= 10;
          baud_cnt  <= DIV - 1;
        end if;
      elsif baud_cnt = 0 then
        -- one bit period elapsed: emit the next bit
        shreg     <= '1' & shreg(9 downto 1);  -- backfill '1' -> idle after stop
        bits_left <= bits_left - 1;
        baud_cnt  <= DIV - 1;
      else
        baud_cnt <= baud_cnt - 1;
      end if;
    end if;
  end process;

end architecture rtl;
