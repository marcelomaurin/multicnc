#!/usr/bin/env python3
"""Build/run suite tests with the same paths on Windows, Linux and CI.

Console binaries can be staged beside the apps for the installed Test Center.
A cross build records 'not-run' explicitly; it never reports tests as passed.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MODULES = [".", "multisuite", "multiphysics", "multicam", "multipcb",
           "laserpcb", "multislicer", "multiassembly", "multicad"]


def execute(command, cwd=ROOT, timeout=120):
    return subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout)


def console(args):
    build = Path(os.environ.get("MULTICNC_BUILD", Path(tempfile.gettempdir()) / "multicnc-build")).resolve()
    flags = shlex.split(os.environ.get("MULTICNC_TEST_FLAGS", ""))
    target_os = next((f[2:] for f in flags if f.startswith("-T")), "win64" if os.name == "nt" else "linux")
    suffix = ".exe" if target_os.startswith("win") else ""
    run_tests = not args.build_only and os.environ.get("MULTICNC_RUN_TESTS", "1") != "0"
    dirs = sorted({p.parent for folder in [ROOT / "src", *ROOT.glob("*/src")]
                   for p in folder.rglob("*.pas") if "lib" not in p.relative_to(ROOT).parts})
    common = [p for p in dirs if "app" not in p.relative_to(ROOT).parts]
    records = []
    for module in args.modules or MODULES:
        tag = "multicnc" if module == "." else module
        src = ROOT / ("src" if module == "." else module + "/src")
        own = [p for p in dirs if p.is_relative_to(src) and
               (module == "." or "app" not in p.relative_to(src).parts)]
        paths = list(dict.fromkeys(own + common))
        for source in sorted((ROOT / module / "tests").glob("*.lpr")):
            if re.search(r"\bInterfaces\s*[,;]", source.read_text(encoding="utf-8"), re.I):
                continue
            output = build / tag / source.stem
            output.mkdir(parents=True, exist_ok=True)
            command = [os.environ.get("FPC", "fpc"), "-Mobjfpc", "-Sh", "-O1", "-vw0",
                       *flags, *("-Fu" + str(p) for p in paths), "-FU" + str(output),
                       "-FE" + str(source.parent), str(source)]
            record = {"source": source.relative_to(ROOT).as_posix(), "status": "build-failed"}
            try:
                result = execute(command)
                (output / "compile.log").write_text(result.stdout, encoding="utf-8")
                if result.returncode:
                    print("BUILD", tag + "/" + source.stem, result.stdout[-3000:])
                    records.append(record)
                    continue
                binary = source.with_suffix(suffix)
                if run_tests:
                    result = execute([str(binary)], cwd=source.parent, timeout=int(os.environ.get("MULTICNC_TEST_TIMEOUT", "30")))
                    record["status"] = "passed" if result.returncode == 0 else "failed"
                    record["exit_code"] = result.returncode
                    (output / "run.log").write_text(result.stdout, encoding="utf-8")
                    last = result.stdout.strip().splitlines()[-1:] or [""]
                    print("PASS" if result.returncode == 0 else "FAIL", tag + "/" + source.stem, last[0])
                else:
                    record["status"] = "not-run"
                    print("BUILD", tag + "/" + source.stem, "(cross build: not run)")
                if args.stage and record["status"] in ("passed", "not-run"):
                    dest = args.stage / binary.relative_to(ROOT)
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(binary, dest)
            except (OSError, subprocess.TimeoutExpired) as error:
                record["status"] = "error"
                record["error"] = str(error)
                print("ERROR", tag + "/" + source.stem, error)
            records.append(record)
    report = {"tests_executed": run_tests, "tests": records}
    report_dir = args.stage if args.stage else build
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / "qa-tests.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    passed = sum(r["status"] == "passed" for r in records)
    failed = sum(r["status"] not in ("passed", "not-run") for r in records)
    print(f"aprovados={passed} falhas={failed} compilados={len(records)}")
    return 1 if failed or not records else 0


def gui(args):
    failed = []
    for project in sorted(ROOT.rglob("*.lpi")):
        if ".git" in project.relative_to(ROOT).parts or "dist" in project.relative_to(ROOT).parts:
            continue
        result = execute([os.environ.get("LAZBUILD", "lazbuild"), "-q", "--ws=gtk2", str(project)], timeout=180)
        if result.returncode:
            print("FAIL", project.relative_to(ROOT), result.stdout[-3000:])
            failed.append(str(project))
        else:
            print("OK", project.relative_to(ROOT))
    if args.run and not failed:
        for name in ("tests/test_app", "multisuite/tests/test_suite_app", "multislicer/tests/test_slicer_app"):
            binary = ROOT / name
            if not binary.exists():
                continue
            result = execute(["xvfb-run", "-a", str(binary)], timeout=30)
            print(result.stdout.strip())
            if result.returncode:
                failed.append(name)
    return int(bool(failed))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest="action", required=True)
    p = actions.add_parser("console")
    p.add_argument("modules", nargs="*")
    p.add_argument("--stage", type=Path)
    p.add_argument("--build-only", action="store_true")
    p = actions.add_parser("gui")
    p.add_argument("--run", action="store_true")
    args = parser.parse_args()
    if getattr(args, "stage", None):
        args.stage = args.stage.resolve()
    return console(args) if args.action == "console" else gui(args)


if __name__ == "__main__":
    sys.exit(main())
