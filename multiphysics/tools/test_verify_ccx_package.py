"""Testes offline do verificador CalculiX: sem rede nem binários reais."""
import hashlib
import io
from pathlib import Path
import tempfile
import unittest
import zipfile

from verify_ccx_package import validate


class PackageValidationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "calculix.zip"

    def build(self, names, *, symlink=False):
        with zipfile.ZipFile(self.path, "w") as z:
            for name in names:
                if symlink and name == "link":
                    info = zipfile.ZipInfo(name)
                    info.create_system = 3
                    info.external_attr = (0o120777 << 16)
                    z.writestr(info, "target")
                else:
                    z.writestr(name, b"dummy")
        return hashlib.sha256(self.path.read_bytes()).hexdigest()

    def test_valid_structure_is_only_inspected(self):
        sha = self.build(["bin/ccx.exe", "bin/runtime.dll"])
        result = validate(self.path, sha)
        self.assertEqual(result["status"], "VERIFICADO_PARA_INSPECAO")
        self.assertEqual(result["ccx"], "bin/ccx.exe")

    def test_hash_mismatch_rejected(self):
        self.build(["ccx.exe"])
        with self.assertRaisesRegex(ValueError, "divergente"):
            validate(self.path, "0" * 64)

    def test_missing_executable_rejected(self):
        sha = self.build(["README.txt"])
        with self.assertRaisesRegex(ValueError, "ccx.exe"):
            validate(self.path, sha)

    def test_duplicate_executable_rejected(self):
        sha = self.build(["a/ccx.exe", "b/ccx.exe"])
        with self.assertRaisesRegex(ValueError, "exatamente um"):
            validate(self.path, sha)

    def test_path_traversal_rejected(self):
        sha = self.build(["../ccx.exe"])
        with self.assertRaisesRegex(ValueError, "inseguro"):
            validate(self.path, sha)

    def test_absolute_path_rejected(self):
        sha = self.build(["/ccx.exe"])
        with self.assertRaisesRegex(ValueError, "inseguro"):
            validate(self.path, sha)

    def test_windows_drive_path_rejected(self):
        sha = self.build(["C:/ccx.exe"])
        with self.assertRaisesRegex(ValueError, "inseguro"):
            validate(self.path, sha)

    def test_symlink_rejected(self):
        sha = self.build(["ccx.exe", "link"], symlink=True)
        with self.assertRaisesRegex(ValueError, "simbólico"):
            validate(self.path, sha)

    def test_invalid_hash_rejected(self):
        self.build(["ccx.exe"])
        with self.assertRaisesRegex(ValueError, "inválido"):
            validate(self.path, "not-a-hash")

    def test_corrupt_zip_rejected(self):
        self.path.write_bytes(b"not a zip")
        sha = hashlib.sha256(self.path.read_bytes()).hexdigest()
        with self.assertRaises(zipfile.BadZipFile):
            validate(self.path, sha)


if __name__ == "__main__":
    unittest.main()
