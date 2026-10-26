#!/usr/bin/env python3
"""Send a program to the rv32i_core bootloader (step 8) over the serial port.

Usage:
  python upload.py <program.bin> [--port COM3] [--monitor] [--baud 115200]
  python upload.py --list

  <program.bin>  raw program image from sw/build/ (made by `make` in sw/)
  --port         the board's serial port. Without it: if exactly one Tang Nano
                 board is connected it is used, otherwise the boards are listed.
  --list         list the connected Tang Nano boards and exit
  --monitor      after a successful upload, keep printing what the board
                 sends (Ctrl+C to stop)

How an upload works (the protocol is described in sw/08_boot.c):
  1. Open the port and ask the user to press S1 (reset) on the board.
  2. The bootloader announces itself with a "[boot] ..." line and waits 1 s.
     As soon as that line is complete, send:
        "UPLD", length (4 bytes, little-endian), the program, CRC-32 (4 bytes)
  3. The bootloader answers "[boot] OK ..." and starts the program, or
     "[boot] ERROR ...".

This file is also the engine of the GUI (upload_gui.py): find_boards(),
read_program() and upload() are used by both.

Needs pyserial: framework_initialise.py installs it into the project's .venv/,
and `make upload` / `make gui` run this file with that Python.
"""

import argparse
import struct
import sys
import time
import zlib

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    sys.exit("pyserial is missing in this Python. Run the tool through make (sw/), or with\n"
             "the project's venv: .venv/bin/python (Windows: .venv\\Scripts\\python);\n"
             "framework_initialise.py creates it.")

BOARD_USB_ID = (0x0403, 0x6010)   # the Tang Nano's USB chip (BL702) presents itself as an FTDI FT2232
MAX_PROGRAM = 0x1F00              # 7936 bytes: RAM above is the bootloader's stack (sw/08_boot.ld)
BAUD = 115200
WAIT_FOR_RESET_S = 30             # how long to wait for S1 to be pressed
REPLY_TIMEOUT_S = 3               # how long to wait for OK / ERROR after sending


class UploadError(Exception):
    """Something went wrong; the message says what, in plain words."""


class Cancelled(UploadError):
    """The user stopped the upload."""


# ---- Finding boards ---------------------------------------------------------------

def find_boards():
    """Connected Tang Nano boards: a list of (port, description), sorted by port."""
    boards = []
    for p in serial.tools.list_ports.comports():
        if (p.vid, p.pid) == BOARD_USB_ID:
            # Windows adds " (COM3)" to the description; the port is shown separately
            desc = (p.description or "USB serial port").replace(f" ({p.device})", "")
            if p.serial_number:
                desc += f", serial {p.serial_number}"
            boards.append((p.device, desc))
    return sorted(boards)


# ---- The program file -------------------------------------------------------------

def read_program(path):
    """Read a .bin file; returns (bytes, crc32). Raises UploadError if unusable."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError as e:
        raise UploadError(f"cannot read {path}: {e.strerror}")
    if not 0 < len(data) <= MAX_PROGRAM:
        raise UploadError(f"{path}: {len(data)} bytes - a program must be 1 to {MAX_PROGRAM} bytes")
    return data, zlib.crc32(data) & 0xFFFFFFFF


def make_packet(data, crc):
    return b"UPLD" + struct.pack("<I", len(data)) + data + struct.pack("<I", crc)


# ---- The protocol ---------------------------------------------------------------------

def _read_line(port, deadline, cancel):
    """One line (up to \\n) before `deadline`, or None. Raises Cancelled."""
    buf = bytearray()
    while time.time() < deadline:
        if cancel is not None and cancel.is_set():
            raise Cancelled("upload cancelled")
        b = port.read(1)
        if not b:
            continue
        if b == b"\n":
            return buf.decode("ascii", "replace").rstrip("\r")
        buf += b
    return None


def print_log(text, kind="info"):
    """Default logger for the command line: just print."""
    print(text)


def upload(port, data, crc, log=print_log, wait_s=WAIT_FOR_RESET_S, cancel=None):
    """Upload `data` through an open serial port. Returns the transfer time in s.

    log(text, kind) is called for every step; kind is "info", "board" or "ok".
    cancel: an optional threading.Event to stop waiting (used by the GUI).
    Raises UploadError (or Cancelled) when it doesn't work.
    """
    port.reset_input_buffer()
    log(f"Press S1 on the board (waiting up to {wait_s} s) ...")
    deadline = time.time() + wait_s
    while True:
        line = _read_line(port, deadline, cancel)
        if line is None:
            raise UploadError("no answer from the bootloader - is the step 8 bitstream on the board, "
                              "and is this the right port?")
        if line.startswith("[boot]"):
            log(f"board: {line}", "board")
            break
        # anything else is output of the program that was running before S1

    # The whole "[boot]" line has arrived, so the bootloader is now listening
    t0 = time.time()
    port.write(make_packet(data, crc))
    port.flush()

    deadline = time.time() + REPLY_TIMEOUT_S + (len(data) + 12) * 10 / BAUD
    while True:
        line = _read_line(port, deadline, cancel)
        if line is None:
            raise UploadError("no reply after sending - the upload state is unknown, press S1 and retry")
        if line.startswith("[boot]"):
            log(f"board: {line}", "board")
            if "OK" in line:
                elapsed = time.time() - t0
                log(f"Upload done in {elapsed:.2f} s.", "ok")
                return elapsed
            if "ERROR" in line:
                raise UploadError("the bootloader reported an error (see above)")


def open_port(name):
    try:
        return serial.Serial(name, BAUD, timeout=0.05)
    except serial.SerialException as e:
        raise UploadError(f"cannot open {name}: {e}\n(is another program, e.g. a terminal, using it?)")


# ---- Command line -----------------------------------------------------------------------

def choose_port(requested):
    """The port to use: the requested one, or the only board connected."""
    if requested:
        return requested
    boards = find_boards()
    if len(boards) == 1:
        print(f"Board: {boards[0][0]} ({boards[0][1]})")
        return boards[0][0]
    if not boards:
        raise UploadError("no Tang Nano board found (USB ID 0403:6010) - is it plugged in?")
    lines = "\n".join(f"  {p}  {d}" for p, d in boards)
    raise UploadError(f"{len(boards)} boards connected - choose one with --port (make: PORT=...):\n{lines}")


def main():
    ap = argparse.ArgumentParser(description="Upload a program to the rv32i_core bootloader (step 8).")
    ap.add_argument("program", nargs="?", help="program image (.bin) from sw/build/")
    ap.add_argument("--port", help="serial port, e.g. COM3 (default: the only board connected)")
    ap.add_argument("--list", action="store_true", help="list connected Tang Nano boards")
    ap.add_argument("--monitor", action="store_true", help="show the program's output afterwards")
    args = ap.parse_args()

    try:
        if args.list:
            boards = find_boards()
            if not boards:
                print("No Tang Nano board found (USB ID 0403:6010).")
            for p, d in boards:
                print(f"{p:8} {d}")
            return
        if not args.program:
            ap.error("give the program file (or --list)")

        data, crc = read_program(args.program)
        print(f"{args.program}: {len(data)} bytes, CRC-32 {crc:08X}")
        port = open_port(choose_port(args.port))
        with port:
            upload(port, data, crc)
            if args.monitor:
                print("--- program output (Ctrl+C to stop) ---")
                try:
                    while True:
                        b = port.read(256)
                        if b:
                            sys.stdout.write(b.decode("ascii", "replace"))
                            sys.stdout.flush()
                except KeyboardInterrupt:
                    print()
    except UploadError as e:
        sys.exit(f"Upload failed: {e}")


if __name__ == "__main__":
    main()
