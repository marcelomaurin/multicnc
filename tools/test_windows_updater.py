"""Exercises the actual PowerShell updater with local network/process fixtures."""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'installer/windows/multisuite_updater.ps1'
PS = shutil.which('powershell.exe')


@unittest.skipUnless(os.name == 'nt' and PS, 'Windows PowerShell required')
class UpdaterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mp-updater-test-')
        self.base = Path(self.temp.name)
        self.setup = self.base / 'fixture.exe'
        self.setup.write_bytes(b'Synthetic installer fixture: never executed')
        self.checksum = self.base / 'SHA256SUMS'
        digest = hashlib.sha256(self.setup.read_bytes()).hexdigest()
        self.checksum.write_text(digest + '  setup_multcnc_0.19.exe\n')
        self.release = dict(tag_name='v0.19', draft=False, prerelease=False, assets=[
            dict(name='setup_multcnc_019.exe', browser_download_url='https://github.com/marcelomaurin/multicnc/releases/download/v0.19/old.exe'),
            dict(name='setup_multcnc_0.19.exe', browser_download_url='https://github.com/marcelomaurin/multicnc/releases/download/v0.19/setup.exe'),
            dict(name='SHA256SUMS', browser_download_url='https://github.com/marcelomaurin/multicnc/releases/download/v0.19/SHA256SUMS')])

    def tearDown(self):
        self.temp.cleanup()

    def run_updater(self, current='0.18', check_only=False):
        env = os.environ.copy()
        env.update(MP_RELEASE=json.dumps(self.release), MP_SETUP=str(self.setup),
                   MP_HASH=str(self.checksum), MP_LAUNCH=str(self.base/'launched'))
        # Windows PowerShell must not inherit PowerShell 7's module directories.
        env.pop('PSModulePath', None)
        quote = lambda s: "'" + str(s).replace("'", "''") + "'"
        code = '''$global:LASTEXITCODE=0
function Invoke-RestMethod { param($Uri,$Headers,$TimeoutSec) return ($env:MP_RELEASE | ConvertFrom-Json) }
function Invoke-WebRequest {
 param($Uri,$OutFile,[switch]$UseBasicParsing,$TimeoutSec)
 if($Uri.EndsWith('SHA256SUMS')) { Copy-Item $env:MP_HASH $OutFile }
 elseif($Uri.EndsWith('setup.exe')) { Copy-Item $env:MP_SETUP $OutFile }
 else { throw 'Wrong installer asset selected' }
}
function Start-Process { param($FilePath,$WindowStyle) [IO.File]::WriteAllText($env:MP_LAUNCH,$FilePath) }
& ''' + quote(SCRIPT) + ' -InstalledVersion ' + quote(current) + ' -StateDirectory ' + quote(self.base/'state')
        code += ' -CheckOnly' if check_only else ' -ForceCheck'
        code += '; exit $LASTEXITCODE'
        encoded = base64.b64encode(code.encode('utf-16le')).decode('ascii')
        return subprocess.run([PS,'-NoProfile','-NonInteractive','-EncodedCommand',encoded],
                              env=env,capture_output=True,text=True,errors='replace',timeout=20)

    def test_download_checksum_and_launch(self):
        r = self.run_updater()
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertTrue((self.base/'launched').exists())
        self.assertIn('setup_multcnc_0.19.exe',(self.base/'launched').read_text())

    def test_bad_checksum_never_launches(self):
        self.checksum.write_text('0'*64+'  setup_multcnc_0.19.exe\n')
        r = self.run_updater()
        self.assertNotEqual(r.returncode,0)
        self.assertFalse((self.base/'launched').exists())

    def test_equivalent_version_does_not_reinstall(self):
        r = self.run_updater(current='0.19.0.0')
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertFalse((self.base/'launched').exists())

    def test_check_only_never_downloads(self):
        r = self.run_updater(check_only=True)
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        data = json.loads(r.stdout)
        self.assertTrue(data['update_available'])
        self.assertFalse(data['installation_performed'])
        self.assertFalse((self.base/'state/release-0.19').exists())
        self.assertFalse((self.base/'launched').exists())

    def test_foreign_download_url_is_rejected(self):
        self.release['assets'][1]['browser_download_url']='https://example.invalid/setup.exe'
        r=self.run_updater()
        self.assertNotEqual(r.returncode,0)
        self.assertFalse((self.base/'launched').exists())


if __name__ == '__main__':
    unittest.main()
