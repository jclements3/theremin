-- dsm_dac.vhd — first-order error-feedback delta-sigma modulator (1-bit DAC).
--
-- Requirements this module implements (verified in dsm_dac_tb.vhd):
--   R1: for a constant (DC) sample, the long-run mean of bit_out equals
--       (sample + 2**(W-1)) / 2**W — i.e. the input mapped to [0, 1) of
--       full scale. The quantization error is pushed to high frequencies
--       (noise shaping), where the external RC filter removes it.
--   R2: synchronous active-high reset clears the error accumulator and
--       holds bit_out at '0' while asserted.
--
-- How it works: the signed sample is first mapped to offset binary
-- (add 2**(W-1), which is just inverting the sign bit). Each clock, the
-- W-bit residual error carried in acc(W-1 downto 0) is added to the input;
-- the carry out of that add — acc(W) — is the output bit, worth exactly
-- 2**W of accumulated input, and the remainder stays behind as the new
-- error. Nothing is ever thrown away, so the ones-density is exact in the
-- long run: this is the error-feedback form of a first-order delta-sigma.
--
-- Radar analog: 1-bit quantization with noise shaping is how exciters and
-- high-speed DACs trade amplitude resolution for oversampling rate; the
-- shaped quantization noise floor is what sets SFDR out of the transmitter.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dsm_dac is
  generic (
    W : positive := 8  -- input sample width
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;               -- synchronous, active-high
    sample  : in  signed(W - 1 downto 0);  -- signed audio sample
    bit_out : out std_logic                -- density-modulated 1-bit output
  );
end entity dsm_dac;

architecture rtl of dsm_dac is
  -- acc(W) is the carry (output bit); acc(W-1 downto 0) is the residual error.
  signal acc        : unsigned(W downto 0) := (others => '0');
  signal offset_bin : unsigned(W - 1 downto 0);
begin

  -- signed -> offset binary: adding 2**(W-1) mod 2**W = inverting the MSB.
  offset_bin(W - 1)          <= not sample(W - 1);
  offset_bin(W - 2 downto 0) <= unsigned(sample(W - 2 downto 0));

  modulate : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        acc <= (others => '0');
      else
        -- residual error + input; carry out becomes the output bit.
        acc <= ('0' & acc(W - 1 downto 0)) + offset_bin;
      end if;
    end if;
  end process;

  bit_out <= acc(W);  -- registered: acc is the only state

end architecture rtl;
