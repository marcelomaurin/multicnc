"""Windows integration tests using a synthetic executable, never a real solver.

These validate installer transactions and failure handling; they do not homologate
any CalculiX distribution. All network downloads are replaced with local fixtures.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

MANAGER = Path(__file__).resolve().parents[2] / 'installer/windows/calculix_manager.ps1'
POWERSHELL = shutil.which('powershell.exe')


def ps(script, env=None):
    encoded = base64.b64encode(script.encode('utf-16le')).decode('ascii')
    return subprocess.run([POWERSHELL, '-NoProfile', '-NonInteractive', '-EncodedCommand', encoded],
                          env=env, capture_output=True, text=True, errors='replace', timeout=30)


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


@unittest.skipUnless(os.name == 'nt' and POWERSHELL, 'Windows PowerShell required')
class ManagerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.shared = tempfile.TemporaryDirectory(prefix='mp-manager-fixture-')
        cls.exe = Path(cls.shared.name) / 'ccx.exe'
        source = '''using System; using System.IO; using System.Threading;
class Fixture { static int Main() {
 string mode=Environment.GetEnvironmentVariable("MP_SOLVER_MODE");
 if(mode=="timeout") Thread.Sleep(10000);
 if(mode=="failure") return 3;
 if(mode=="missing") return 0;
 File.WriteAllText("smoke.dat", "displacements (vx,vy,vz)\\n 2 " +
   (mode=="wrong"?"9.0":"4.457142857142857E-03") + " 0 0\\n");
 Console.WriteLine("SYNTHETIC FIXTURE - NOT CALCULIX"); return 0;
} }'''
        result = ps("Add-Type -TypeDefinition " + quote(source) +
                    ' -OutputAssembly ' + quote(cls.exe) + ' -OutputType ConsoleApplication')
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.shared.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mp-manager-test-')
        self.base = Path(self.temp.name)
        self.root = self.base / 'managed'
        self.archive = self.base / 'package.zip'
        self.manifest = self.base / 'manifest.json'
        self.package()

    def tearDown(self):
        self.temp.cleanup()

    def package(self, version='2.23', extra=None, license=True, dependency=True):
        with zipfile.ZipFile(self.archive, 'w') as z:
            z.write(self.exe, 'bin/ccx.exe')
            if license:
                z.writestr('COPYING', 'Synthetic test fixture license; not a CalculiX package')
            if dependency:
                z.writestr('bin/runtime.dll', 'fixture dependency')
            if extra:
                z.writestr(*extra)
        self.metadata = dict(version=version, url='https://tests.invalid/fixture.zip',
                             sha256=hashlib.sha256(self.archive.read_bytes()).hexdigest(),
                             executable='bin/ccx.exe', licenseFile='COPYING',
                             requiredFiles=['bin/runtime.dll'])
        self.manifest.write_text(json.dumps(self.metadata), encoding='utf8')

    def invoke(self, action='Install', mode='', extra='', offline=False, held_lock=False):
        env = os.environ.copy()
        env.update(MP_SOLVER_MODE=mode, MP_PACKAGE=str(self.archive))
        script = "$ErrorActionPreference='Stop'; "
        script += '''function Invoke-WebRequest {
 param($Uri,$OutFile,[switch]$UseBasicParsing,$TimeoutSec)
 ''' + ("throw 'offline fixture'" if offline else 'Copy-Item -LiteralPath $env:MP_PACKAGE -Destination $OutFile') + ' }; '
        if held_lock:
            self.root.mkdir(exist_ok=True)
            script += '$held=[IO.File]::Open(' + quote(self.root / 'manager.lock') + ",'OpenOrCreate','ReadWrite','None'); "
        script += 'try { & ' + quote(MANAGER) + ' -Root ' + quote(self.root) + ' -Action ' + action
        if action == 'Install' and not extra:
            script += ' -ManifestPath ' + quote(self.manifest)
        script += ' -TestTimeoutSec 1 ' + extra + '; exit 0 } catch { Write-Output $_.Exception.Message; exit 9 }'
        return ps(script, env)

    def active(self):
        return (self.root / 'active.txt').read_text(encoding='utf8').strip()

    def assert_rejected(self, **kwargs):
        result = self.invoke(**kwargs)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.root / 'active.txt').exists())
        self.assertFalse(list(self.root.glob('staging-*')))
        return result

    def test_install_upgrade_rollback(self):
        self.package(version='2.22')
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        old = self.active()
        self.package(version='2.23')
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        current = self.active()
        self.assertNotEqual(current, old)
        self.assertEqual((self.root / 'previous.txt').read_text().strip(), old)
        result = self.invoke(action='Rollback')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.active(), old)
        self.assertEqual((self.root / 'previous.txt').read_text().strip(), current)

    def test_failed_upgrade_preserves_active(self):
        self.package(version='2.22')
        self.assertEqual(self.invoke().returncode, 0)
        old = self.active()
        self.package(version='2.23')
        result = self.invoke(mode='wrong')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.active(), old)
        self.assertFalse((self.root / 'versions/2.23').exists())

    def test_repeat_active_version_is_idempotent(self):
        self.assertEqual(self.invoke().returncode, 0)
        old = self.active()
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.active(), old)

    def test_approved_catalog_without_manual_manifest(self):
        catalog = self.base / 'catalog.json'
        entry = dict(self.metadata, status='approved', platform='windows', arch='x64')
        catalog.write_text(json.dumps(dict(schemaVersion=1, policy='deny-unverified', entries=[entry])))
        result = self.invoke(extra='-Version 2.23 -CatalogPath ' + quote(catalog))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(self.active().endswith('ccx.exe'))

    def test_failed_pointer_commit_preserves_previous(self):
        self.package(version='2.22')
        self.assertEqual(self.invoke().returncode, 0)
        old = self.active()
        active = self.root / 'active.txt'
        active.chmod(0o444)
        try:
            self.package(version='2.23')
            result = self.invoke()
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.active(), old)
            self.assertFalse((self.root / 'previous.txt').exists())
            self.assertFalse((self.root / 'versions/2.23').exists())
        finally:
            active.chmod(0o666)

    def test_corrupt_hash(self):
        self.metadata['sha256'] = '0' * 64
        self.manifest.write_text(json.dumps(self.metadata))
        self.assertIn('SHA256 mismatch', self.assert_rejected().stdout)

    def test_path_traversal(self):
        self.package(extra=('../escaped.txt', 'bad'))
        self.assert_rejected()
        self.assertFalse((self.base / 'escaped.txt').exists())

    def test_symlink(self):
        entry = zipfile.ZipInfo('link')
        entry.create_system = 3
        entry.external_attr = 0o120777 << 16
        self.package(extra=(entry, '../outside'))
        self.assert_rejected()

    def test_missing_dependency(self):
        self.package(dependency=False)
        self.assertIn('dependency missing', self.assert_rejected().stdout)

    def test_missing_license(self):
        self.package(license=False)
        self.assertIn('license file required', self.assert_rejected().stdout)

    def test_solver_failure(self):
        self.assertIn('CalculiX failed', self.assert_rejected(mode='failure').stdout)

    def test_missing_result(self):
        self.assertIn('did not produce', self.assert_rejected(mode='missing').stdout)

    def test_solver_timeout(self):
        self.assertIn('timeout', self.assert_rejected(mode='timeout').stdout)

    def test_offline(self):
        self.assert_rejected(offline=True)

    def test_concurrent_manager(self):
        self.assert_rejected(held_lock=True)

    def test_unapproved_catalog(self):
        result = self.assert_rejected(extra='-Version 2.23')
        self.assertIn('not approved', result.stdout)


if __name__ == '__main__':
    unittest.main()
