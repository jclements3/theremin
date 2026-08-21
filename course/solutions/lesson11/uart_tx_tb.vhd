-- uart_tx_tb.vhd — self-checking testbench for the 8N1 UART transmitter.
--
-- Verification approach: the TB is an INDEPENDENT serial decoder. It never
-- looks inside the DUT — it watches txd like a receiver would: find the
-- falling start edge, wait half a bit, then sample mid-bit at the IDEAL
-- baud period (1 sec / BAUD), not at the DUT's integer divider. The DUT's
-- divider truncation (104 vs 104.17 clocks/bit, 0.16 % fast) drifts the
-- sample points by ~1.4 % of a bit over the whole frame — mid-bit sampling
-- absorbs it, exactly as a real receiver's does.
--
-- Requirements verified (R1..R4 from uart_tx.vhd):
--   R1 framing: start bit low and stop bit high at their mid-bit samples.
--   R2 payload: 8 mid-bit samples, lsb first, equal the byte sent
--      (checked for 0x55, 0x00, 0xFF, 0xA5).
--   R3 handshake: busy rises on accept, is still high mid-frame while stb
--      is hammered with a different byte, falls after the stop bit; the
--      hammered byte neither corrupts the frame nor queues a second one.
--   R4 idle: txd stays high out of reset, between frames, and after the
--      ignored-stb test (watched over multi-bit windows, not spot-checked).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx_tb is
end entity uart_tx_tb;

architecture sim of uart_tx_tb is
  constant CLK_HZ   : positive := 12_000_000;
  constant BAUD     : positive := 115_200;
  constant CLK_PER  : time     := 83.333 ns;      -- 12 MHz
  constant BIT_TIME : time     := 1 sec / BAUD;   -- ideal baud period (8680.6 ns),
                                                  -- independent of the DUT divider
  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal data : std_logic_vector(7 downto 0) := (others => '0');
  signal stb  : std_logic := '0';
  signal busy : std_logic;
  signal txd  : std_logic;
  signal done : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.uart_tx
    generic map (
      CLK_HZ => CLK_HZ,
      BAUD   => BAUD
    )
    port map (
      clk  => clk,
      rst  => rst,
      data => data,
      stb  => stb,
      busy => busy,
      txd  => txd
    );

  main : process
    -- Watch txd for 'dur': any falling edge fails (line must idle high).
    procedure check_idle_high(dur : time; tag : string) is
    begin
      wait until txd = '0' for dur;  -- resumes early only if txd falls
      assert txd = '1'
        report tag & " FAIL: txd went low during an idle window"
        severity error;
    end procedure;

    -- Offer one byte for exactly one clock; busy must rise (R3).
    procedure send_byte(b : std_logic_vector(7 downto 0)) is
    begin
      data <= b;
      stb  <= '1';
      wait until rising_edge(clk);
      stb  <= '0';
      wait for 1 ns;  -- let post-edge values settle
      assert busy = '1'
        report "R3 FAIL: busy not asserted on the accept edge"
        severity error;
    end procedure;

    -- Decode one frame off txd by mid-bit sampling (R1, R2). With
    -- poke=true, hammer stb with the complement byte during data bits
    -- 2..5 — the DUT must ignore it (R3).
    procedure decode_frame(expected : std_logic_vector(7 downto 0);
                           poke     : boolean := false) is
      variable rx : std_logic_vector(7 downto 0);
    begin
      if txd = '1' then
        wait until txd = '0' for 20 * BIT_TIME;  -- hunt for the start edge
      end if;
      assert txd = '0'
        report "R1 FAIL: no start bit within 20 bit times"
        severity failure;
      wait for BIT_TIME / 2;
      assert txd = '0'
        report "R1 FAIL: start bit not low at mid-bit"
        severity error;
      for i in 0 to 7 loop
        wait for BIT_TIME;
        rx(i) := txd;  -- 8N1 sends the lsb first
        if poke and i = 1 then      -- R3: offer a different byte mid-frame
          data <= not expected;
          stb  <= '1';
        end if;
        if poke and i = 5 then
          assert busy = '1'
            report "R3 FAIL: busy dropped mid-frame"
            severity error;
          stb <= '0';
        end if;
      end loop;
      wait for BIT_TIME;  -- mid-stop
      assert txd = '1'
        report "R1 FAIL: stop bit not high at mid-bit"
        severity error;
      report "R1 pass: start/stop framing ok (byte 0x" & to_hstring(expected) & ")";
      assert rx = expected
        report "R2 FAIL: sent 0x" & to_hstring(expected) &
               " but decoded 0x" & to_hstring(rx)
        severity error;
      report "R2 pass: decoded payload 0x" & to_hstring(rx) & " matches";
    end procedure;

    -- After mid-stop, busy must fall when the stop bit completes (R3).
    procedure end_frame is
    begin
      wait until busy = '0' for 2 * BIT_TIME;
      assert busy = '0'
        report "R3 FAIL: busy not released after the stop bit"
        severity error;
      wait until rising_edge(clk);
    end procedure;
  begin
    -- synchronous reset, then release
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert busy = '0'
      report "R3 FAIL: busy asserted out of reset"
      severity error;

    -- R4: line idles high before anything is sent
    check_idle_high(4 * BIT_TIME, "R4");
    report "R4 pass: txd idles high out of reset";

    -- R1/R2: alternating, all-zeros and all-ones payloads
    send_byte(x"55");  decode_frame(x"55");  end_frame;
    report "R3 pass: busy rose on accept and fell after the stop bit";
    send_byte(x"00");  decode_frame(x"00");  end_frame;
    send_byte(x"FF");  decode_frame(x"FF");  end_frame;

    -- R4: line returns to idle between frames
    check_idle_high(3 * BIT_TIME, "R4");
    report "R4 pass: txd idles high between frames";

    -- R3: hammer stb with 0x5A while 0xA5 is in flight — must be ignored
    send_byte(x"A5");  decode_frame(x"A5", poke => true);  end_frame;
    check_idle_high(3 * BIT_TIME, "R3");
    report "R3 pass: stb while busy ignored (payload intact, nothing queued)";

    report "uart_tx testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
