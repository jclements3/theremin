-- theremin_top.vhd — the finished instrument: every verified block from
-- lessons 04-13 wired per the curriculum signal chain.
--
--   osc_in -> sync_2ff -> freq_meas -> pitch_map -> nco -> sine_lut -> dsm_dac -> audio_out
--     (L09)      (L10)       (L13)     (L04)      (L07)     (L08)
--
-- Requirements this module implements (verified in theremin_top_tb.vhd):
--   R1: the design self-starts: a power-on-reset counter (pattern from
--       fpga/phase1/rtl/top.vhd) holds the chain in reset for the first 15
--       clocks after configuration, then releases it; audio_out shows
--       delta-sigma activity shortly after with no external reset pin.
--   R2: with the hand far away (antenna oscillator at its 200 kHz base),
--       the audio fundamental settles to C4 (fcw = FCW_BASE = 93640,
--       f = 261.6 Hz) — the calibrated reference point of the instrument.
--   R3/R4: as the hand approaches (oscillator pulled down in frequency),
--       the audio fundamental tracks it per the lesson13 mapping:
--       fcw = clamp(FCW_BASE + (P_REF - period)*2**SHIFT).
--   R5: pitch is monotonic in hand position end-to-end: more hand
--       capacitance -> longer measured period -> lower fcw -> lower note.
--
-- All pitch_map generics stay at their defaults — the curriculum pins them
-- to this exact integration scenario (12 MHz clock, 200 kHz oscillator,
-- EDGES = 64 => P_REF = 3840; FCW_BASE = C4; clamps C3..C6).
--
-- Registered boundaries: every block in the chain registers its output
-- (freq_meas's period/valid, pitch_map's fcw, nco's phase, sine_lut's data,
-- dsm_dac's bit), so no combinational path crosses more than one module.
--
-- Radar analog: this is system integration against a target model —
-- the whole chain is proven end-to-end in simulation (osc_model standing in
-- for the antenna hardware) before the bench ever sees a bitstream.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity theremin_top is
  port (
    clk12     : in  std_logic;  -- 12 MHz board oscillator
    osc_in    : in  std_logic;  -- antenna relaxation oscillator (async, ~200 kHz)
    audio_out : out std_logic;  -- delta-sigma bitstream: RC filter -> amp
    led_hb    : out std_logic   -- heartbeat, ~0.7 Hz
  );
end entity theremin_top;

architecture rtl of theremin_top is
  signal por_cnt : unsigned(3 downto 0)  := (others => '0');
  signal rst     : std_logic;
  signal hb_cnt  : unsigned(23 downto 0) := (others => '0');

  signal osc_sync : std_logic;
  signal period   : unsigned(23 downto 0);
  signal valid    : std_logic;
  signal fcw      : unsigned(31 downto 0);
  signal phase    : unsigned(31 downto 0);
  signal sample   : signed(7 downto 0);
begin

  -- Boards have no reset button: hold the chain in reset for the first 15
  -- clocks after configuration (same POR as fpga/phase1/rtl/top.vhd).
  rst <= '1' when por_cnt /= x"F" else '0';

  housekeeping : process (clk12)
  begin
    if rising_edge(clk12) then
      if por_cnt /= x"F" then
        por_cnt <= por_cnt + 1;
      end if;
      hb_cnt <= hb_cnt + 1;
    end if;
  end process;

  led_hb <= hb_cnt(23);  -- 12 MHz / 2**24 ~= 0.72 Hz

  -- The antenna oscillator is the only asynchronous input in the design;
  -- it crosses into the 12 MHz domain here and nowhere else.
  u_sync : entity work.sync_2ff
    port map (
      clk      => clk12,
      async_in => osc_in,
      sync_out => osc_sync
    );

  u_meas : entity work.freq_meas
    generic map (
      EDGES    => 64,   -- => P_REF = 64 * 12e6/200e3 = 3840 in pitch_map
      CNT_BITS => 24
    )
    port map (
      clk    => clk12,
      rst    => rst,
      sig_in => osc_sync,
      period => period,
      valid  => valid
    );

  -- Defaults only: the curriculum pins pitch_map's generics to this
  -- integration (P_REF 3840, FCW_BASE C4, clamps C3..C6, slope 2**6).
  u_map : entity work.pitch_map
    port map (
      clk    => clk12,
      rst    => rst,
      period => period,
      valid  => valid,
      fcw    => fcw
    );

  u_nco : entity work.nco
    generic map (W => 32)
    port map (
      clk    => clk12,
      rst    => rst,
      en     => '1',
      fcw    => fcw,
      phase  => phase,
      sq_out => open  -- square tap unused: the sine path is the voice
    );

  u_lut : entity work.sine_lut
    generic map (
      PHASE_BITS => 10,
      DATA_BITS  => 8
    )
    port map (
      clk   => clk12,
      phase => phase(31 downto 22),  -- top 10 bits: phase truncation, lesson07
      data  => sample
    );

  u_dac : entity work.dsm_dac
    generic map (W => 8)
    port map (
      clk     => clk12,
      rst     => rst,
      sample  => sample,
      bit_out => audio_out
    );

end architecture rtl;
