#!/usr/bin/env bash
# attach-fpga.sh — hand the Lattice board's FTDI chip from Windows to WSL2.
#
# Run from WSL each time the board is (re)plugged:  ./attach-fpga.sh
# First time only, the device must be bound from an *elevated* PowerShell:
#   usbipd bind --busid <BUSID>
# (this script prints the busid and detects that case).
set -euo pipefail

if ! command -v usbipd.exe >/dev/null 2>&1; then
  echo "usbipd-win not found. Install from elevated PowerShell:"
  echo "  winget install --exact --id dorssel.usbipd-win"
  exit 1
fi

LIST=$(usbipd.exe list | tr -d '\r')
BUSID=$(awk '/0403:6010|0403:6014/ {print $1; exit}' <<<"$LIST")

if [ -z "$BUSID" ]; then
  echo "No FTDI device (0403:6010 / 0403:6014) found. Is the board plugged in?"
  echo "--- usbipd list ---"
  echo "$LIST"
  exit 1
fi
echo "FTDI device at busid $BUSID"

if grep -q "$BUSID.*Not shared" <<<"$LIST"; then
  echo "Device not yet shared. One-time step, from an ELEVATED PowerShell:"
  echo "  usbipd bind --busid $BUSID"
  exit 1
fi

usbipd.exe attach --wsl --busid "$BUSID"
sleep 1
echo "--- WSL now sees ---"
lsusb | grep -i '0403:' || { echo "Device did not appear in WSL."; exit 1; }
echo "OK — 'make prog' should work now."
