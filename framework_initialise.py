#!/usr/bin/env python3
"""Set up the tools for tangnano9k-riscv-dvi on this PC (Windows or Linux, x86-64).

Run it once from the repository folder:

    python framework_initialise.py            # asks before each big step
    python framework_initialise.py --yes      # no questions

What it does (details in SETUP.md):
  1. checks Python, pyserial (offers to install it) and make
  2. downloads the RISC-V compiler, xPack GNU RISC-V Embedded GCC 15.2.0-1,
     checks its SHA-256 against the one xPack publishes, and unpacks it into
     toolchain/riscv-gcc/
  3. downloads OSS CAD Suite 2024-12-08 (yosys, nextpnr, iverilog,
     openFPGALoader ...), checks its size, and unpacks it into
     toolchain/oss-cad-suite/
     (steps 2 and 3 also run the tools once to check they work)
  4. writes local_paths.mk (tool paths for sw/Makefile)
  5. rebuilds the CPU programs and checks they come out byte-identical to the
     .hex files in the repository

These are the exact versions the project was developed and measured with.
toolchain/ and local_paths.mk are not part of the repository (see .gitignore):
they are about 3 GB once unpacked and depend on this PC. Running the script
again skips what is already installed.

Options:
  --yes            don't ask, answer yes to everything
  --gcc-bin DIR    use an already installed GCC (the folder with riscv-none-elf-gcc)
  --oss-cad DIR    use an already installed OSS CAD Suite (the folder that contains bin/)
  --keep-downloads keep the downloaded archives in toolchain/downloads/
  --no-build-check skip step 5
"""

import argparse
import hashlib
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import urllib.request
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent
TOOLCHAIN = REPO / "toolchain"
DOWNLOADS = TOOLCHAIN / "downloads"

GCC_VERSION = "15.2.0-1"
GCC_BASE = f"https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v{GCC_VERSION}/"
OSS_CAD_TAG = "2024-12-08"
OSS_CAD_BASE = f"https://github.com/YosysHQ/oss-cad-suite-build/releases/download/{OSS_CAD_TAG}/"

DOWNLOAD = {
    #            GCC archive                                          OSS CAD Suite archive
    "windows": (f"xpack-riscv-none-elf-gcc-{GCC_VERSION}-win32-x64.zip",
                f"oss-cad-suite-windows-x64-{OSS_CAD_TAG.replace('-', '')}.exe"),
    "linux":   (f"xpack-riscv-none-elf-gcc-{GCC_VERSION}-linux-x64.tar.gz",
                f"oss-cad-suite-linux-x64-{OSS_CAD_TAG.replace('-', '')}.tgz"),
}

EXE = ".exe" if os.name == "nt" else ""
ASSUME_YES = False


# ---- small helpers -------------------------------------------------------------------

def step(title):
    print(f"\n=== {title} ===")


def ask(question):
    if ASSUME_YES:
        print(f"{question} [y/n] y")
        return True
    while True:
        a = input(f"{question} [y/n] ").strip().lower()
        if a in ("y", "yes"):
            return True
        if a in ("n", "no"):
            return False


def fail(message):
    print(f"\nERROR: {message}")
    sys.exit(1)


def run(cmd, env=None, cwd=None):
    """Run a command; returns (exit code, combined output)."""
    try:
        r = subprocess.run(cmd, env=env, cwd=cwd, capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
        return r.returncode, (r.stdout + r.stderr).strip()
    except OSError as e:
        return -1, str(e)


def download(url, dest):
    """Download url to dest with a progress line; returns the number of bytes."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": "framework_initialise"})
    with urllib.request.urlopen(req) as r, open(tmp, "wb") as f:
        total = int(r.headers.get("Content-Length") or 0)
        done = 0
        last = -1
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
            done += len(chunk)
            if total:
                pct = done * 100 // total
                if pct != last:
                    print(f"\r  {dest.name}: {done >> 20} of {total >> 20} MB ({pct}%)", end="", flush=True)
                    last = pct
    print()
    if total and done != total:
        tmp.unlink()
        fail(f"{dest.name}: download incomplete ({done} of {total} bytes) - run the script again")
    tmp.replace(dest)
    return done


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def extract_tar(archive, dest):
    with tarfile.open(archive) as t:
        if hasattr(tarfile, "tar_filter"):          # Python 3.12+: refuse paths outside dest
            t.extractall(dest, filter="tar")
        else:
            t.extractall(dest)


def to_make_path(p):
    return str(Path(p)).replace("\\", "/")


# ---- the steps --------------------------------------------------------------------------

def check_basics():
    step("1. Python, pyserial, make")
    if sys.version_info < (3, 8):
        fail(f"Python 3.8 or newer is needed, this is {platform.python_version()}")
    print(f"  Python {platform.python_version()}: {sys.executable}")

    machine = platform.machine().lower()
    if sys.platform.startswith("win"):
        system = "windows"
    elif sys.platform.startswith("linux"):
        system = "linux"
    else:
        fail(f"{sys.platform} is not supported by this script (Windows and Linux only); see SETUP.md")
    if machine not in ("amd64", "x86_64"):
        fail(f"only x86-64 PCs are supported, this is {machine}")

    try:
        import serial                                # noqa: F401
        print("  pyserial: installed")
    except ImportError:
        print("  pyserial: missing (needed by the upload tools)")
        if ask("  Install it now with pip (for this user)?"):
            code, out = run([sys.executable, "-m", "pip", "install", "--user", "pyserial"])
            print("  " + (out.splitlines()[-1] if out else ""))
            if code != 0:
                fail("pip could not install pyserial - see the message above")
        else:
            print("  skipped: install it later with  python -m pip install pyserial")

    make = shutil.which("make")
    if make:
        print(f"  make: {make}")
    else:
        print("  make: NOT FOUND - needed to build the CPU programs (sw/Makefile).")
        if system == "windows":
            print("        Install for example with:  winget install ezwinports.make")
            print("        (or Chocolatey: choco install make, or MSYS2); then open a new terminal.")
        else:
            print("        Install it with your package manager, e.g.  sudo apt install make")
    return system, make


def install_gcc(system, given):
    step(f"2. RISC-V compiler (xPack GCC {GCC_VERSION})")
    if given:
        gcc_bin = Path(given).resolve()
    else:
        gcc_bin = TOOLCHAIN / "riscv-gcc" / f"xpack-riscv-none-elf-gcc-{GCC_VERSION}" / "bin"
        if (gcc_bin / f"riscv-none-elf-gcc{EXE}").exists():
            print(f"  already installed: {gcc_bin}")
        else:
            name = DOWNLOAD[system][0]
            if not ask(f"  Download {name} (about 450 MB) and unpack it into toolchain/riscv-gcc/?"):
                fail("the compiler is needed; or give an installed one with --gcc-bin")
            archive = DOWNLOADS / name
            download(GCC_BASE + name, archive)
            # xPack publishes the SHA-256 of every archive in a .sha file next to it
            sha_file = DOWNLOADS / (name + ".sha")
            download(GCC_BASE + name + ".sha", sha_file)
            expected = sha_file.read_text().split()[0].lower()
            actual = sha256_of(archive)
            if actual != expected:
                archive.unlink()
                fail(f"{name}: SHA-256 mismatch (got {actual}, xPack says {expected}) - download again")
            print("  SHA-256 matches xPack's published value")
            print("  unpacking ...")
            dest = TOOLCHAIN / "riscv-gcc"
            if name.endswith(".zip"):
                with zipfile.ZipFile(archive) as z:
                    z.extractall(dest)
            else:
                extract_tar(archive, dest)

    gcc = gcc_bin / f"riscv-none-elf-gcc{EXE}"
    code, out = run([str(gcc), "--version"])
    if code != 0:
        fail(f"the compiler does not run: {gcc}\n{out}")
    print(f"  {out.splitlines()[0]}")
    return gcc_bin


def oss_cad_env(oss):
    """Environment in which the OSS CAD Suite tools run (Windows needs bin and lib on PATH)."""
    env = dict(os.environ)
    extra = [str(oss / "bin")] + ([str(oss / "lib")] if os.name == "nt" else [])
    env["PATH"] = os.pathsep.join(extra + [env.get("PATH", "")])
    return env


def install_oss_cad(system, given):
    step(f"3. OSS CAD Suite {OSS_CAD_TAG}")
    if given:
        oss = Path(given).resolve()
    else:
        oss = TOOLCHAIN / "oss-cad-suite"
        if (oss / "bin" / f"yosys{EXE}").exists():
            print(f"  already installed: {oss}")
        else:
            name = DOWNLOAD[system][1]
            size = "about 290 MB" if system == "windows" else "about 610 MB"
            if not ask(f"  Download {name} ({size}) and unpack it into toolchain/oss-cad-suite/?"):
                fail("OSS CAD Suite is needed; or give an installed one with --oss-cad")
            archive = DOWNLOADS / name
            n = download(OSS_CAD_BASE + name, archive)
            # YosysHQ publishes no checksums; the download is checked by HTTPS and its
            # exact size, and the tools are run below. The SHA-256 is printed so it can
            # be compared with someone else's.
            print(f"  {n} bytes, SHA-256 {sha256_of(archive)}")
            print("  unpacking ...")
            if system == "windows":
                # The Windows package is a self-extracting 7-Zip archive: -o<folder> -y
                # unpacks it without questions; it creates oss-cad-suite/ inside <folder>.
                code, out = run([str(archive), f"-o{TOOLCHAIN}", "-y"])
                if code != 0:
                    fail(f"unpacking failed:\n{out}")
            else:
                extract_tar(archive, TOOLCHAIN)
            if not (oss / "bin" / f"yosys{EXE}").exists():
                fail(f"after unpacking, {oss / 'bin'} has no yosys - unexpected archive layout")

    env = oss_cad_env(oss)
    checks = [
        (["yosys", "-V"], "Yosys"),
        (["nextpnr-himbaechel", "--version"], "nextpnr"),
        (["iverilog", "-V"], "Icarus Verilog"),
        (["openFPGALoader", "--Version"], "openFPGALoader"),
    ]
    for cmd, expect in checks:
        exe = shutil.which(cmd[0], path=env["PATH"])
        if not exe:
            fail(f"{cmd[0]} not found in {oss / 'bin'}")
        code, out = run([exe] + cmd[1:], env=env)
        line = next((l for l in out.splitlines() if expect.lower() in l.lower()), None)
        if line is None:
            fail(f"{cmd[0]} does not run properly:\n{out[:500]}")
        print(f"  {line.strip()[:90]}")
    return oss


def write_local_paths(gcc_bin, oss):
    step("4. local_paths.mk")
    path = REPO / "local_paths.mk"
    path.write_text(
        "# Tool paths of this PC, written by framework_initialise.py.\n"
        "# Not part of the repository (see .gitignore); format: local_paths.example.mk\n"
        f"GCC_BIN := {to_make_path(gcc_bin)}\n"
        f"OSS_CAD := {to_make_path(oss)}\n"
        f"PYTHON := {to_make_path(sys.executable)}\n",
        encoding="utf-8")
    print(f"  written: {path}")


def check_build(make):
    step("5. Build check: rebuild the CPU programs")
    if not make:
        print("  skipped: make is not installed (see step 1)")
        return
    # the .hex files sw/Makefile writes (font.hex and screen.hex come from tools/, not from make)
    hexes = sorted(p for p in REPO.glob("0*_*/*.hex") if p.name not in ("font.hex", "screen.hex"))
    before = {p: sha256_of(p) for p in hexes}
    code, out = run([make, "-B"], cwd=REPO / "sw")
    if code != 0:
        fail(f"make failed in sw/:\n{out[-2000:]}")
    changed = [p for p in hexes if sha256_of(p) != before[p]]
    if changed:
        print("  WARNING: these files came out different from the repository version:")
        for p in changed:
            print(f"    {p.relative_to(REPO)}")
        print("  (a different compiler version would explain it; the designs still work,")
        print("   but the numbers in notes/ were measured with the files in the repository)")
    else:
        print(f"  {len(hexes)} program images rebuilt, all byte-identical to the repository")


def main():
    global ASSUME_YES
    ap = argparse.ArgumentParser(description="Set up the tools for tangnano9k-riscv-dvi.")
    ap.add_argument("--yes", action="store_true", help="answer yes to every question")
    ap.add_argument("--gcc-bin", help="use an installed GCC (folder with riscv-none-elf-gcc)")
    ap.add_argument("--oss-cad", help="use an installed OSS CAD Suite (folder containing bin/)")
    ap.add_argument("--keep-downloads", action="store_true", help="keep toolchain/downloads/")
    ap.add_argument("--no-build-check", action="store_true", help="don't rebuild the programs")
    args = ap.parse_args()
    ASSUME_YES = args.yes

    print(f"tangnano9k-riscv-dvi: setting up the tools in {REPO}")
    free = shutil.disk_usage(REPO).free
    if free < 4 << 30 and not (args.gcc_bin and args.oss_cad):
        print(f"Note: only {free >> 30} GB free here; downloads and unpacked tools need about 4 GB.")

    system, make = check_basics()
    gcc_bin = install_gcc(system, args.gcc_bin)
    oss = install_oss_cad(system, args.oss_cad)
    write_local_paths(gcc_bin, oss)
    if not args.no_build_check:
        check_build(make)

    if DOWNLOADS.exists() and not args.keep_downloads:
        shutil.rmtree(DOWNLOADS)
        print("\n  (downloaded archives removed; use --keep-downloads to keep them)")

    step("Done")
    print("Last manual step - tell Lushay Code (VS Code) where OSS CAD Suite is:")
    print("  VS Code > Settings > search 'lushay' > OssCadSuite: Path =")
    print(f"      {oss}")
    print("  (check the User AND the Workspace tab - see SETUP.md)")
    print("Then open the repository folder in VS Code and build 00_blinky as a first test.")


if __name__ == "__main__":
    main()
