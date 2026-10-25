#!/usr/bin/env python3
"""A small window for uploading programs to the rv32i_core bootloader (step 8).

Start:  python upload_gui.py      (or `make gui` in sw/)

  Board    the connected Tang Nano boards (refresh after plugging one in)
  Program  a .bin from sw/build/ (made by `make` in sw/)
  Upload   then press S1 on the board when asked; the log shows whether the
           upload worked (Cancel stops waiting for S1)

Same protocol and code as the command line: everything that talks to the
board is in upload.py; this file is only the window around it.
The last board and program are remembered in ~/.rv32i_upload.json.
"""

import json
import os
import queue
import sys
import threading
import tkinter as tk
from tkinter import filedialog, ttk
from tkinter.scrolledtext import ScrolledText

# upload.py lives next to this file. Python's -I mode (isolated) doesn't put the
# script's folder on the import path, so add it explicitly.
sys.dont_write_bytecode = True      # no __pycache__ folder next to the project's files
TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS_DIR)
import upload as engine            # noqa: E402

BUILD_DIR = os.path.normpath(os.path.join(TOOLS_DIR, "..", "sw", "build"))
SETTINGS = os.path.join(os.path.expanduser("~"), ".rv32i_upload.json")


def load_settings():
    try:
        with open(SETTINGS, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_settings(values):
    try:
        with open(SETTINGS, "w", encoding="utf-8") as f:
            json.dump(values, f, indent=2)
    except OSError:
        pass                        # remembering is a convenience, not essential


class App:
    def __init__(self, root):
        self.root = root
        self.settings = load_settings()
        self.events = queue.Queue()     # messages from the worker thread to the window
        self.worker = None
        self.cancel = threading.Event()
        self.boards = []

        root.title("rv32i bootloader upload")
        root.minsize(560, 360)
        frame = ttk.Frame(root, padding=10)
        frame.grid(sticky="nsew")
        root.columnconfigure(0, weight=1)
        root.rowconfigure(0, weight=1)
        frame.columnconfigure(1, weight=1)
        frame.rowconfigure(4, weight=1)

        # Board
        ttk.Label(frame, text="Board:").grid(row=0, column=0, sticky="w", pady=2)
        self.board = ttk.Combobox(frame, state="readonly")
        self.board.grid(row=0, column=1, sticky="ew", padx=4)
        ttk.Button(frame, text="Refresh", command=self.refresh_boards).grid(row=0, column=2, sticky="ew")

        # Program
        ttk.Label(frame, text="Program:").grid(row=1, column=0, sticky="w", pady=2)
        self.program = tk.StringVar(value=self.default_program())
        self.program.trace_add("write", lambda *_: self.show_program_info())
        ttk.Entry(frame, textvariable=self.program).grid(row=1, column=1, sticky="ew", padx=4)
        ttk.Button(frame, text="Browse...", command=self.browse).grid(row=1, column=2, sticky="ew")
        self.info = ttk.Label(frame, foreground="gray")
        self.info.grid(row=2, column=1, sticky="w", padx=4)

        # Buttons
        buttons = ttk.Frame(frame)
        buttons.grid(row=3, column=0, columnspan=3, sticky="ew", pady=(6, 6))
        self.cancel_btn = ttk.Button(buttons, text="Cancel", command=self.cancel.set, state="disabled")
        self.cancel_btn.pack(side="right")
        self.upload_btn = ttk.Button(buttons, text="Upload", command=self.start_upload)
        self.upload_btn.pack(side="right", padx=4)

        # Log
        self.log = ScrolledText(frame, height=12, width=72, state="disabled", font=("Consolas", 9))
        self.log.grid(row=4, column=0, columnspan=3, sticky="nsew")
        self.log.tag_config("board", foreground="#0050a0")
        self.log.tag_config("ok", foreground="#007000")
        self.log.tag_config("error", foreground="#c00000")

        self.refresh_boards()
        self.show_program_info()
        root.protocol("WM_DELETE_WINDOW", self.close)
        self.poll_id = root.after(50, self.poll_events)

    # ---- Inputs -----------------------------------------------------------------------

    def default_program(self):
        last = self.settings.get("program")
        if last and os.path.exists(last):
            return last
        candidate = os.path.join(BUILD_DIR, "07_terminal.bin")
        return candidate if os.path.exists(candidate) else ""

    def refresh_boards(self):
        self.boards = engine.find_boards()
        labels = [f"{port} - {desc}" for port, desc in self.boards]
        self.board["values"] = labels
        if not labels:
            self.board.set("")
            self.write("No Tang Nano board found (USB ID 0403:6010). Plug it in and press Refresh.",
                       "error")
            return
        ports = [port for port, _ in self.boards]
        last = self.settings.get("port")
        self.board.current(ports.index(last) if last in ports else 0)

    def browse(self):
        start = os.path.dirname(self.program.get()) or BUILD_DIR
        path = filedialog.askopenfilename(
            title="Program to upload", initialdir=start if os.path.isdir(start) else BUILD_DIR,
            filetypes=[("Program image", "*.bin"), ("All files", "*.*")])
        if path:
            self.program.set(os.path.normpath(path))

    def show_program_info(self):
        path = self.program.get()
        if not path:
            self.info.config(text="choose a .bin from sw/build (run make in sw/ first)")
            return
        try:
            data, crc = engine.read_program(path)
            self.info.config(text=f"{os.path.basename(path)}: {len(data)} bytes, CRC-32 {crc:08X}")
        except engine.UploadError as e:
            self.info.config(text=str(e))

    # ---- Upload (runs in a worker thread, so the window stays responsive) ---------------

    def start_upload(self):
        if self.worker and self.worker.is_alive():
            return
        if not self.boards or self.board.current() < 0:
            self.write("Choose a board first.", "error")
            return
        port_name = self.boards[self.board.current()][0]
        try:
            data, crc = engine.read_program(self.program.get())
        except engine.UploadError as e:
            self.write(str(e), "error")
            return
        self.settings.update(port=port_name, program=self.program.get())
        self.settings.pop("monitor", None)          # option of an earlier version
        save_settings(self.settings)

        self.write(f"--- {os.path.basename(self.program.get())} -> {port_name} ---")
        self.cancel.clear()
        self.set_busy(True)
        self.worker = threading.Thread(target=self.run_upload, args=(port_name, data, crc), daemon=True)
        self.worker.start()

    def run_upload(self, port_name, data, crc):
        log = lambda text, kind="info": self.events.put(("log", text, kind))
        try:
            with engine.open_port(port_name) as port:     # closed again right after
                engine.upload(port, data, crc, log=log, cancel=self.cancel)
        except engine.Cancelled:
            log("Cancelled.", "info")
        except engine.UploadError as e:
            log(f"Upload failed: {e}", "error")
        except Exception as e:                       # an unexpected problem: show it, don't hang
            log(f"Unexpected error: {e!r}", "error")
        finally:
            self.events.put(("done",))

    def set_busy(self, busy):
        self.upload_btn.config(state="disabled" if busy else "normal")
        self.cancel_btn.config(state="normal" if busy else "disabled")

    # ---- Window plumbing ----------------------------------------------------------------

    def poll_events(self):
        try:
            while True:
                ev = self.events.get_nowait()
                if ev[0] == "log":
                    _, text, kind = ev
                    self.write(text, kind)
                elif ev[0] == "done":
                    self.set_busy(False)
        except queue.Empty:
            pass
        self.poll_id = self.root.after(50, self.poll_events)

    def write(self, text, kind="info"):
        self.log.config(state="normal")
        self.log.insert("end", text + "\n", () if kind == "info" else (kind,))
        self.log.see("end")
        self.log.config(state="disabled")

    def close(self):
        self.cancel.set()                    # stops a running upload
        self.root.after_cancel(self.poll_id) # otherwise Tk calls poll_events after the window is gone
        self.root.destroy()


def create_root():
    """The main window. On Windows, first declare the program "DPI aware": with
    display scaling (e.g. 125%) Windows would otherwise stretch the window as a
    bitmap, which makes the text blurry."""
    if sys.platform == "win32":
        try:
            import ctypes
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except (AttributeError, OSError):
            pass                    # older Windows: keep the default
    return tk.Tk()


def main():
    root = create_root()
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
