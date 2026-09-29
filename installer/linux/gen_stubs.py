#!/usr/bin/env python3
"""Generate link-time stub shared libraries for a cross target.

For each host (amd64) library, read its exported dynamic symbols and emit a
tiny .so for the target with the same SONAME and the same symbol names
(functions as empty bodies, data objects as zero-filled arrays of the same
size). The cross linker resolves against these; at runtime the target system
loads the real libraries by SONAME. The stubs are never shipped.

usage: gen_stubs.py <cross-gcc> <outdir> <soname> [<soname> ...]
"""
import os
import re
import subprocess
import sys

HOST_LIBDIR = "/usr/lib/x86_64-linux-gnu"


def symbols(path):
    out = subprocess.run(["readelf", "-W", "--dyn-syms", path],
                         capture_output=True, text=True, check=True).stdout
    funcs, objs = {}, {}
    for line in out.splitlines():
        parts = line.split()
        # Num: Value Size Type Bind Vis Ndx Name
        if len(parts) < 8 or not parts[0].rstrip(":").isdigit():
            continue
        _, _, size, typ, bind, _, ndx, name = parts[:8]
        if ndx == "UND" or bind not in ("GLOBAL", "WEAK"):
            continue
        name = name.split("@")[0]
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
            continue
        if typ in ("FUNC", "IFUNC"):
            funcs[name] = bind
        elif typ in ("OBJECT", "TLS"):
            sz = int(size, 0) if size.startswith("0x") else int(size)
            objs[name] = (max(sz, 1), bind)
    return funcs, objs


def main():
    cc, outdir, sonames = sys.argv[1], sys.argv[2], sys.argv[3:]
    os.makedirs(outdir, exist_ok=True)
    for soname in sonames:
        host = os.path.join(HOST_LIBDIR, soname)
        funcs, objs = symbols(host)
        src = os.path.join(outdir, soname + ".c")
        with open(src, "w") as f:
            for n, b in sorted(funcs.items()):
                attr = "__attribute__((weak)) " if b == "WEAK" else ""
                f.write(f"{attr}void {n}(void){{}}\n")
            for n, (sz, b) in sorted(objs.items()):
                attr = "__attribute__((weak)) " if b == "WEAK" else ""
                f.write(f"{attr}char {n}[{sz}];\n")
        target = os.path.join(outdir, soname)
        subprocess.run([cc, "-shared", "-nostdlib", "-fno-builtin", "-w",
                        f"-Wl,-soname,{soname}", "-o", target, src], check=True)
        # unversioned dev symlink: libfoo.so -> libfoo.so.N
        dev = re.sub(r"\.so\..*$", ".so", soname)
        link = os.path.join(outdir, dev)
        if os.path.lexists(link):
            os.remove(link)
        os.symlink(soname, link)
        os.remove(src)
        print(f"{soname}: {len(funcs)} funcoes, {len(objs)} dados")


if __name__ == "__main__":
    main()
