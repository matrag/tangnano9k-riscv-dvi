# Setting up

[Back to the README](README.md)

This guide recreates the working environment the project was developed in:
the same tool versions, the same folder layout. The setup script needs a few
minutes plus the download time for about 730 MB (Windows) or 1 GB (Linux);
on the development PC the whole run took 4.5 minutes.

**Supported:** Windows 10/11 and Linux, on x86-64 PCs. The script and this
guide are tested on Windows; on Linux the setup script is tested on Debian 12,
but building, flashing and uploading from Linux have not been tried yet -
please report what you find.

## 1. What you need

**Hardware**

- a Sipeed **Tang Nano 9K** board and a USB-C cable
- a monitor with an HDMI input, and an HDMI cable (the board sends DVI video,
  which every HDMI monitor accepts)

**Disk space:** about 4 GB for the tools (downloads are deleted afterwards).

**Install by hand** (the script can't do these for you):

| Tool | Why | Where |
|---|---|---|
| **Python 3.8 or newer** | runs the setup script, the converters and the upload tool | Windows: [python.org](https://www.python.org/downloads/) - tick *Add python.exe to PATH* in the installer. Linux: usually installed (`python3`); on Debian/Ubuntu also install `python3-venv` and `python3-tk` (see below). |
| **make** | builds the CPU software (`sw/Makefile`) | Windows: e.g. `winget install ezwinports.make`, or `choco install make` (Chocolatey), or MSYS2. Linux: `sudo apt install make` (or your distribution's equivalent). |
| **VS Code** + the **Lushay Code** extension | builds the FPGA designs, flashes the board, runs testbenches | [code.visualstudio.com](https://code.visualstudio.com/), then in VS Code: Extensions, search *Lushay Code*. Optional if you build from the command line (section 7). |

On Debian or Ubuntu, one command installs everything of this table except VS Code:

```
sudo apt install python3 python3-venv python3-tk make
```

Open a **new** terminal after installing, so it finds the new programs.

## 2. Get the repository

Download it as a zip from GitHub and unpack it, or clone it with git. The
folder is called "the repository folder" below; any location works, but avoid
paths with spaces if you can.

## 3. Run the setup script

In a terminal, in the repository folder:

```
python framework_initialise.py
```

(on Linux: `python3 framework_initialise.py`). It asks before each download;
`--yes` answers yes to everything. What it does:

| Step | What | Where it goes |
|---|---|---|
| 1 | checks Python and make | - |
| 2 | creates the project's **virtual environment** and installs **pyserial 3.5** into it (for the upload tools); checks **tkinter** (for the upload window) | `.venv/` |
| 3 | downloads **xPack GNU RISC-V Embedded GCC 15.2.0-1** (Windows ~450 MB, Linux ~410 MB), checks its SHA-256 against the value xPack publishes, unpacks it, runs it | `toolchain/riscv-gcc/` |
| 4 | downloads **OSS CAD Suite 2024-12-08** (Windows ~290 MB, Linux ~610 MB) - yosys, nextpnr, Project Apicula, iverilog, openFPGALoader - checks the download is complete, unpacks it, runs each tool once | `toolchain/oss-cad-suite/` |
| 5 | writes the tool paths and the venv's Python for `make` | `local_paths.mk` |
| 6 | rebuilds the CPU programs and checks they are byte-identical to the `.hex` files in the repository | - |
| 7 | Linux only: checks that you may open the board's serial port and USB device, and prints the commands to fix it if not (section 5) | - |

**Why a virtual environment:** current Linux distributions don't allow `pip
install` into the system's Python (the error says *externally-managed-environment*),
so the project keeps its one Python package, pyserial, in its own `.venv/`
folder - on Windows too, so both work the same way. You never need to
activate it: `make` calls the venv's Python directly.

These are the exact versions the project was developed and measured with.
The downloads come from the official GitHub release pages:
[xPack GCC](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/tag/v15.2.0-1),
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases/tag/2024-12-08).
YosysHQ publishes no checksums for OSS CAD Suite, so that download is checked
by its size and by running the tools; the script prints its SHA-256 so you can
compare it with someone else's. For reference, the Windows package
`oss-cad-suite-windows-x64-20241208.exe` (299,271,845 bytes) downloaded while
testing this guide had SHA-256
`8f52a429dceb560270b7ab6f02f688ac556c9e511030389c93234dbcae028186`.

`toolchain/`, `.venv/` and `local_paths.mk` belong to your PC and are not part of the
repository (`.gitignore`). Running the script again skips what is already
installed.

**Already have the tools?** Use them instead of downloading:

```
python framework_initialise.py --gcc-bin <folder with riscv-none-elf-gcc> --oss-cad <OSS CAD Suite folder>
```

Other versions may produce slightly different results; step 6 tells you if
the compiled programs differ from the repository's.

## 4. Map the tool paths

Two programs need to know where the tools are.

**make** (the CPU software) reads `local_paths.mk` in the repository folder:
the compiler's folder and the Python to use (the venv's).
The script writes it; to write it by hand, copy `local_paths.example.mk` to
`local_paths.mk` and fill in your paths (forward slashes also on Windows).

**Lushay Code** has its own setting:

1. In VS Code: *File > Preferences > Settings*, search for **lushay**.
2. Set **Lushay > Oss Cad Suite: Path** to the OSS CAD Suite folder - the
   script prints it at the end, e.g. `<repository folder>/toolchain/oss-cad-suite`.
   Use the folder that *contains* `bin`, not `bin` itself.
3. Look at both tabs at the top of the settings, **User** and **Workspace**: a
   value in *Workspace* overrides *User*. An old Workspace value is a common
   reason for errors like `ENOENT ... stat 'C:\oss-cad-suite\bin'`.

## 5. Connect the board and find its port

Plug the board in with USB-C. Its USB chip provides two channels: one for
programming the FPGA (used by Lushay / openFPGALoader) and one serial port (the
UART of steps 7 and 8).

- **Windows:** the serial port appears in Device Manager under *Ports (COM & LPT)*
  as *USB Serial Port (COMn)*.
- **Linux:** it appears as `/dev/ttyUSBn`. Two permissions are needed; step 7
  of the setup script checks both and prints these commands if one is missing:
  - the **serial port**: your user must be in the `dialout` group (Arch Linux:
    `uucp`): `sudo usermod -aG dialout $USER`, then log out and back in;
  - the **USB device**, for openFPGALoader to program the FPGA: a udev rule for
    the board's USB ID `0403:6010`:
    ```
    echo 'ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="664", GROUP="plugdev", TAG+="uaccess"' | sudo tee /etc/udev/rules.d/99-tangnano9k.rules
    sudo udevadm control --reload-rules && sudo udevadm trigger
    ```
    then unplug the board and plug it in again.

To list the connected boards: in `sw/`, run `make ports`.

## 6. First test

1. Open the **repository folder** in VS Code (*File > Open Folder*).
2. Click **FPGA Toolchain** in the status bar, choose **Build and Program**, then
   `blinky.lushay.json`.
3. The six LEDs count in binary; S1 resets the count.

Then work through the steps: each folder has a page in `notes/steps/` that
says what to look for. Step 8's bootloader lets you upload programs without
rebuilding the FPGA (`make gui` or `make upload` in `sw/`).

## 7. Building without Lushay Code

Lushay runs four commands, which you can run yourself with OSS CAD Suite's
`bin` folder on the PATH (on Windows also its `lib` folder, or run its
`environment.bat` first). For a step folder, take the file list from
`includedFiles` and the top module from `top` in its `*.lushay.json`:

```
yosys -p "read_verilog <files>; synth_gowin -top top -json build.json"
nextpnr-himbaechel --json build.json --write build_pnr.json --freq 27 \
    --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C --vopt cst=tangnano9k.cst \
    --chipdb <OSS CAD Suite>/share/nextpnr/himbaechel/gowin/chipdb-GW1N-9C.bin
gowin_pack -d GW1N-9C -o build.fs build_pnr.json
openFPGALoader -b tangnano9k build.fs -v -f
```

Run them **in the step folder**: the designs load their `.hex` files with
paths relative to it. `-f` writes the design into the board's flash, so it
stays after power-off; without `-f` it is loaded only until the next power-off.

Testbenches: `iverilog -o sim.vvp -s test <testbench> <files>` then `vvp sim.vvp`,
also in the step folder. Every testbench prints `PASS` or `FAIL`.

## 8. If something doesn't work

| Symptom | Cause / fix |
|---|---|
| Lushay: `ENOENT ... stat '...oss-cad-suite\bin'` | the OSS CAD Suite path is wrong - check the *Workspace* tab too (section 4) |
| Lushay: *No files to synthesize* | a `*.lushay.json` without `includedFiles` - every project here lists its files |
| OSS CAD tools exit at once on Windows (code -1073741515) | their `lib` folder is not on the PATH (only `bin`) |
| `make: riscv-none-elf-gcc: No such file or directory` | `local_paths.mk` missing or wrong - run the setup script again |
| Setup script: *could not create the virtual environment* (Linux) | `sudo apt install python3-venv`, then run the script again |
| `make gui`: *No module named 'tkinter'* | `sudo apt install python3-tk` (Fedora: `python3-tkinter`); `make upload` works without it |
| *pyserial is missing* / *No module named 'serial'* | the tool runs with a Python without pyserial - run it through `make`, or with the venv's Python (`.venv/bin/python`, Windows `.venv\Scripts\python`); run the setup script again if `.venv/` is gone |
| Linux: upload tool *Permission denied: '/dev/ttyUSB1'* | not in the `dialout` group, or not logged out and in since (section 5) |
| Linux: openFPGALoader *unable to open ftdi device* / *LIBUSB_ERROR_ACCESS* | the udev rule is missing, or the board was not replugged after adding it (section 5) |
| Upload tool: *cannot open COMn* | another program (a serial terminal) has the port open |
| Upload tool: *no answer from the bootloader* | the step 8 bitstream is not on the board, or S1 was not pressed |

More traps and their explanations: [notes/gotchas.md](notes/gotchas.md).
