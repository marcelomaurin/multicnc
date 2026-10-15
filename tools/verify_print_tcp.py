#!/usr/bin/env python3
"""Build and run actual MultiSlicer -> MultiCNC -> SimuCNC TCP integration.
Windows: python tools/verify_print_tcp.py (FPC/LAZARUS_DIR may be supplied).
Linux: xvfb-run -a python3 tools/verify_print_tcp.py (LCL GTK2 required).
No physical serial device is opened. Port 9000 must be free.
"""
import json
import os
from pathlib import Path
import shlex
import sys
import tempfile
import verify_suite as suite


def main():
    root = suite.ROOT
    output = Path(os.environ.get('MULTICNC_BUILD', Path(tempfile.gettempdir()) / 'multicnc-build')) / 'print-tcp'
    output.mkdir(parents=True, exist_ok=True)
    flags = shlex.split(os.environ.get('MULTICNC_TEST_FLAGS', ''))
    compiler = os.environ.get('FPC', 'fpc')
    dirs = sorted({p.parent for folder in [root/'src', *root.glob('*/src')]
                   for p in folder.rglob('*.pas') if 'lib' not in p.relative_to(root).parts})
    deps = suite.dependency_flags()
    if os.name != 'nt':
        # Use a real GUI event loop for the server's TCP polling timer.
        deps = ['-Fu'+str(p) for p in Path('/usr/lib/lazarus').glob('*/lcl/units/*/gtk2')] + deps
    suffix = '.exe' if os.name == 'nt' else ''
    results = []
    for name in ['test_simucnc_server', 'test_multicnc_tcp']:
        build = output/name
        build.mkdir(exist_ok=True)
        result = suite.execute([compiler, '-Mobjfpc', '-Sh', '-O1', *flags, *deps,
            *('-Fu'+str(p) for p in dirs), '-FU'+str(build), '-FE'+str(output),
            str(root/'tests'/(name+'.lpr'))], timeout=180)
        (output/(name+'-build.log')).write_text(result.stdout, encoding='utf-8')
        results.append({'source': 'tests/'+name+'.lpr', 'build_exit_code': result.returncode})
        if result.returncode:
            print(result.stdout[-4000:])
            return result.returncode
    os.environ['SIMUCNC_TEST_SERVER'] = str(output/('test_simucnc_server'+suffix))
    result = suite.execute([sys.executable, str(root/'tests/test_simucnc_tcp.py'),
        str(output/('test_multicnc_tcp'+suffix)), str(output/'print.gcode'),
        str(output/'session.log')], timeout=220)
    (output/'run.log').write_text(result.stdout, encoding='utf-8')
    (output/'result.json').write_text(json.dumps({'tests': results,
        'status': 'passed' if result.returncode == 0 else 'failed',
        'exit_code': result.returncode}, indent=2)+'\n', encoding='utf-8')
    print(result.stdout)
    return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
