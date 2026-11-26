"""Run the open-source ibtool under Python audit hooks (no OS sandbox in this container).

Usage: python3 -I ibsandbox.py <OUTPUT ROOT> <SOURCE ROOT> <IBTOOL DIR> [ibtool args...]

Blocks network, processes, ctypes and fork; writes, deletes and renames outside
OUTPUT ROOT; reads outside SOURCE ROOT, IBTOOL DIR and the Python library. A blocked
action stops the run with exit code 99.
"""
import os
import sys
import sysconfig

out_root, src_root, tool = (os.path.realpath(p) for p in sys.argv[1:4])
# This script too: a traceback reads its source lines.
read_roots = [src_root, tool, out_root, os.path.realpath(__file__)] + sorted(
    {os.path.realpath(p) for p in sysconfig.get_paths().values() if p}
)
DENY_PREFIXES = ("socket.", "subprocess.", "ctypes.", "os.exec", "os.spawn", "os.posix_spawn",
                 "os.fork", "os.forkpty", "os.system", "os.kill", "pty.", "urllib.", "http.",
                 "ftplib.", "smtplib.", "webbrowser.", "winreg.", "os.chmod", "os.chown",
                 "os.symlink", "os.link", "sys.setprofile", "sys.settrace", "code.", "compile")
DENY_MODULES = {"ctypes", "socket", "subprocess", "_socket", "_ctypes", "ssl", "urllib",
                "http", "pty", "multiprocessing", "_posixsubprocess", "marshal", "pickle"}
PATH_WRITE_EVENTS = {"os.remove", "os.rmdir", "os.mkdir", "os.rename", "os.replace",
                     "os.truncate", "shutil.rmtree", "shutil.copyfile", "shutil.move",
                     "os.utime"}


def inside(path, roots):
    try:
        p = os.path.realpath(os.fsdecode(path))
    except (TypeError, ValueError):
        return False
    return any(p == r or p.startswith(r + os.sep) for r in roots)


def stop(event, args):
    os.write(2, f"SANDBOX BLOCKED: {event} {str(args)[:200]}\n".encode())
    os._exit(99)


def hook(event, args):
    if event == "compile":
        return  # the import system compiles the tool's own .py files
    if event.startswith(DENY_PREFIXES):
        stop(event, args)
    if event == "import" and args[0].split(".")[0] in DENY_MODULES:
        stop(event, args)
    if event == "open":
        path, mode, flags = args
        if isinstance(path, int):
            return
        writing = (mode and any(c in mode for c in "wax+")) or (
            flags and flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC))
        if writing and not inside(path, [out_root]):
            stop(event, args)
        if not writing and not inside(path, read_roots):
            stop(event, args)
    if event in PATH_WRITE_EVENTS:
        for a in args[:2]:
            if isinstance(a, (str, bytes, os.PathLike)) and not inside(a, [out_root]):
                stop(event, args)


# Imports the tool needs, done before the hook so the deny list stays strict.
import getopt, plistlib, random, shutil, struct, xml.etree.ElementTree  # noqa: E401,F401,E402

sys.dont_write_bytecode = True  # no __pycache__ folder in the tool folder
sys.addaudithook(hook)
sys.path.insert(0, tool)
sys.argv = ["ibtool.py"] + sys.argv[4:]
import ibtool  # noqa: E402
import traceback  # noqa: E402

try:
    ibtool.main()
except Exception as error:  # report without reading source lines (the guard denies them)
    frames = [f"{os.path.basename(f.f_code.co_filename)}:{line}"
              for f, line in traceback.walk_tb(error.__traceback__)]
    os.write(2, f"{type(error).__name__}: {str(error)[:150]} at {frames[-1]}\n".encode())
    os._exit(1)
