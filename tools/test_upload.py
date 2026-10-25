#!/usr/bin/env python3
"""Tests for upload.py (the upload engine), without a board.

Run:  python -I test_upload.py      (prints OK at the end if all pass)

A FakeBoard stands in for the serial port. It behaves like the bootloader in
sw/08_boot.c: it prints a "[boot]" line, receives "UPLD" + length + program +
CRC-32, checks the CRC and answers OK or ERROR. It also records whether the
upload started only after the whole "[boot]" line had been read - the rule
that keeps the board's 16-byte receive FIFO from overflowing.
"""

import os
import struct
import sys
import tempfile
import threading
import time
import unittest
import zlib

sys.dont_write_bytecode = True      # no __pycache__ folder next to the project's files
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import upload  # noqa: E402

BANNER = b"\r\n[boot] rv32i_core bootloader - waiting 1 s for an upload\r\n"


class FakeBoard:
    """A serial-port look-alike that answers like the bootloader."""

    def __init__(self, before=b"", banner=True, corrupt=False):
        self.out = bytearray(before + (BANNER if banner else b""))   # bytes the PC will read
        self.banner_end = len(self.out) if banner else None           # index just after the banner's \n
        self.read_pos = 0
        self.rx = bytearray()                                         # bytes the PC wrote
        self.corrupt = corrupt                                        # damage one byte "on the cable"
        self.write_started_at = None                                  # read_pos when the PC first wrote
        self.received = None                                          # program as stored by the "board"

    # --- the pyserial methods upload() uses ---
    def reset_input_buffer(self):
        pass

    def read(self, n=1):
        if self.read_pos < len(self.out):
            chunk = bytes(self.out[self.read_pos:self.read_pos + n])
            self.read_pos += len(chunk)
            return chunk
        time.sleep(0.001)                                             # like a serial timeout
        return b""

    def write(self, data):
        if self.write_started_at is None:
            self.write_started_at = self.read_pos
        self.rx += data
        self._handle()

    def flush(self):
        pass

    # --- the "bootloader" ---
    def _handle(self):
        if len(self.rx) < 8 or self.rx[:4] != b"UPLD":
            return
        length = struct.unpack("<I", self.rx[4:8])[0]
        if len(self.rx) < 8 + length + 4:
            return
        data = bytearray(self.rx[8:8 + length])
        if self.corrupt:
            data[len(data) // 2] ^= 0x10
        crc_sent = struct.unpack("<I", self.rx[8 + length:12 + length])[0]
        self.received = bytes(data)
        if zlib.crc32(data) & 0xFFFFFFFF == crc_sent:
            self.out += b"[boot] OK - starting the uploaded program\r\n"
        else:
            self.out += b"[boot] ERROR: CRC mismatch, the data was damaged - waiting for a new upload\r\n"


def quiet(text, kind="info"):
    pass


class UploadTests(unittest.TestCase):

    PROGRAM = bytes(range(256)) * 5 + b"tail"          # 1284 bytes

    def run_upload(self, board, **kw):
        crc = zlib.crc32(self.PROGRAM) & 0xFFFFFFFF
        return upload.upload(board, self.PROGRAM, crc, log=quiet, **kw)

    def test_good_upload(self):
        board = FakeBoard()
        self.run_upload(board)
        self.assertEqual(board.received, self.PROGRAM)

    def test_waits_for_the_end_of_the_boot_line(self):
        board = FakeBoard()
        self.run_upload(board)
        self.assertEqual(board.write_started_at, board.banner_end,
                         "the upload must start right after the [boot] line's \\n, not earlier")

    def test_packet_format(self):
        board = FakeBoard()
        self.run_upload(board)
        crc = zlib.crc32(self.PROGRAM) & 0xFFFFFFFF
        self.assertEqual(bytes(board.rx), b"UPLD" + struct.pack("<I", len(self.PROGRAM))
                         + self.PROGRAM + struct.pack("<I", crc))

    def test_output_of_the_old_program_is_skipped(self):
        board = FakeBoard(before=b"uptime 00:00:01\r\nHello from the FPGA!\r\n")
        self.run_upload(board)
        self.assertEqual(board.received, self.PROGRAM)

    def test_crc_error_is_reported(self):
        with self.assertRaises(upload.UploadError):
            self.run_upload(FakeBoard(corrupt=True))

    def test_no_bootloader(self):
        with self.assertRaises(upload.UploadError) as ctx:
            self.run_upload(FakeBoard(banner=False), wait_s=0.3)
        self.assertIn("no answer", str(ctx.exception))

    def test_cancel(self):
        cancel = threading.Event()
        threading.Timer(0.1, cancel.set).start()
        with self.assertRaises(upload.Cancelled):
            self.run_upload(FakeBoard(banner=False), wait_s=5, cancel=cancel)


class ProgramFileTests(unittest.TestCase):

    def write_tmp(self, data):
        f = tempfile.NamedTemporaryFile(delete=False, suffix=".bin")
        f.write(data)
        f.close()
        self.addCleanup(os.remove, f.name)
        return f.name

    def test_crc_matches_zlib(self):
        data = b"\x13\x05\xa0\x00" * 100
        got, crc = upload.read_program(self.write_tmp(data))
        self.assertEqual((got, crc), (data, zlib.crc32(data) & 0xFFFFFFFF))

    def test_empty_file_rejected(self):
        with self.assertRaises(upload.UploadError):
            upload.read_program(self.write_tmp(b""))

    def test_largest_allowed(self):
        upload.read_program(self.write_tmp(b"\0" * upload.MAX_PROGRAM))

    def test_too_big_rejected(self):
        with self.assertRaises(upload.UploadError):
            upload.read_program(self.write_tmp(b"\0" * (upload.MAX_PROGRAM + 1)))


class ChoosePortTests(unittest.TestCase):

    def with_boards(self, boards):
        original = upload.find_boards
        upload.find_boards = lambda: boards
        self.addCleanup(setattr, upload, "find_boards", original)

    def test_requested_port_wins(self):
        self.with_boards([("COM3", "a"), ("COM8", "b")])
        self.assertEqual(upload.choose_port("COM8"), "COM8")

    def test_single_board_is_used(self):
        self.with_boards([("COM3", "a")])
        self.assertEqual(upload.choose_port(None), "COM3")

    def test_no_board(self):
        self.with_boards([])
        with self.assertRaises(upload.UploadError):
            upload.choose_port(None)

    def test_several_boards_need_a_choice(self):
        self.with_boards([("COM3", "a"), ("COM8", "b")])
        with self.assertRaises(upload.UploadError) as ctx:
            upload.choose_port(None)
        self.assertIn("COM8", str(ctx.exception))


if __name__ == "__main__":
    unittest.main(verbosity=2)
