#!/usr/bin/env python3
"""Record the source commit, compiler, architecture and hashes in distributions."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import struct
import subprocess


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_architecture(app, target_os, arch):
    names = ("multisuite", "multicad", "multiassembly", "multiphysics",
             "multicam", "multislicer", "laserpcb", "laserart", "multicnc", "multisuite_test_center",
             "makepcb", "makerouter", "routerpcb")
    if target_os == "windows":
        names = tuple(name for name in names if name not in ("multisuite", "multisuite_test_center")) + ("multisuite_tray", "SimuCNC")
    required = {app / (name + (".exe" if target_os == "windows" else "")) for name in names}
    valid = set()
    for path in app.rglob("*"):
        if not path.is_file():
            continue
        with path.open("rb") as stream:
            head = stream.read(64)
            if head.startswith(b"\x7fELF"):
                if len(head) < 20:
                    raise SystemExit("Cabecalho ELF truncado: " + str(path))
                expected = {"amd64": 62, "arm64": 183, "armhf": 40}.get(arch)
                expected_class = 1 if arch == "armhf" else 2
                machine = struct.unpack_from("<H" if head[5] == 1 else ">H", head, 18)[0]
                if target_os != "linux" or machine != expected or head[4] != expected_class:
                    raise SystemExit("Arquitetura ELF incorreta: " + str(path))
                if arch == "armhf":
                    if len(head) < 52:
                        raise SystemExit("Cabecalho ELF32 truncado: " + str(path))
                    order = "<" if head[5] == 1 else ">"
                    kind = struct.unpack_from(order + "H", head, 16)[0]
                    flags = struct.unpack_from(order + "I", head, 36)[0]
                    # AAELF32 5.2: executable ABI is declared in e_flags.
                    # Tag_ABI_VFP_args is an object compatibility attribute
                    # and is not present in every valid FPC executable.
                    if (kind not in (2, 3) or flags >> 24 < 5 or
                            not flags & 0x400 or flags & 0x200):
                        raise SystemExit(f"ARM sem ABI hard-float (e_flags=0x{flags:x}): {path}")
                valid.add(path)
            elif head.startswith(b"MZ"):
                if len(head) < 64:
                    raise SystemExit("Cabecalho PE truncado: " + str(path))
                stream.seek(struct.unpack_from("<I", head, 60)[0])
                pe = stream.read(6)
                expected = {"amd64": 0x8664}.get(arch)
                if target_os != "windows" or pe[:4] != b"PE\0\0" or len(pe) < 6 or struct.unpack_from("<H", pe, 4)[0] != expected:
                    raise SystemExit("Arquitetura PE incorreta: " + str(path))
                valid.add(path)
    missing = required - valid
    if missing:
        raise SystemExit("Aplicacoes ausentes/invalidas: " + ", ".join(str(p) for p in sorted(missing)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-dir", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--os", required=True, choices=("linux", "windows"))
    parser.add_argument("--arch", required=True, choices=("amd64", "arm64", "armhf"))
    parser.add_argument("--require-clean", action="store_true")
    parser.add_argument("--version-include", type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?(?:[-+~][A-Za-z0-9.+~-]+)?", args.version):
        raise SystemExit("Use uma versao como 0.1.1 ou 0.1.1-dev.")
    repo = Path(__file__).resolve().parents[1]
    os.chdir(repo)
    dirty = bool(command("git", "status", "--porcelain"))
    if args.require_clean and dirty:
        raise SystemExit("A release exige uma arvore Git limpa; registre as alteracoes primeiro.")
    app = args.app_dir.resolve()
    verify_architecture(app, args.os, args.arch)
    if args.version_include:
        parts = re.match(r"(\d+\.\d+(?:\.\d+)?)", args.version).group(1).split(".")
        numeric = ".".join(parts + ["0"] * (4 - len(parts)))
        args.version_include.write_text('#define MyAppVersion "' + args.version + '"\n' +
                                       '#define MyBinaryVersion "' + numeric + '"\n', encoding="utf-8")
    qa = json.loads((app / "qa-tests.json").read_text(encoding="utf-8"))
    manifest = {
        "version": args.version, "source_commit": command("git", "rev-parse", "HEAD"),
        "source_dirty": dirty, "os": args.os, "arch": args.arch,
        "host": platform.platform(), "fpc": command(os.environ.get("FPC", "fpc"), "-iV"),
        "lazarus": command(os.environ.get("LAZBUILD", "lazbuild"), "--version"),
        "console_tests_executed": qa["tests_executed"],
        "console_tests": len(qa["tests"]),
        "files": [{"path": p.relative_to(app).as_posix(), "sha256": sha256(p)}
                  for p in sorted(app.rglob("*")) if p.is_file() and p.name != "build-manifest.json"],
    }
    (app / "build-manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
