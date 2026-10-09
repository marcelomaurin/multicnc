"""Release validation rejects missing apps and mixed architectures."""
import hashlib
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("release_manifest", Path(__file__).resolve().parents[1] / "tools/release_manifest.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)
NAMES = ("multisuite", "multicad", "multipcb", "multiassembly", "multiphysics",
         "multicam", "multislicer", "laserpcb", "laserart", "multicnc", "multisuite_test_center")


def elf(machine=62, bits=2, flags=0):
    data = bytearray(64)
    data[:6] = b"\x7fELF" + bytes((bits, 1))
    struct.pack_into("<H", data, 18, machine)
    struct.pack_into("<H", data, 16, 2)
    struct.pack_into("<I", data, 36 if bits == 1 else 48, flags)
    return data


def pe(machine=0x8664):
    data = bytearray(256)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 60, 128)
    data[128:132] = b"PE\0\0"
    struct.pack_into("<H", data, 132, machine)
    return data


class ReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.app = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def fill(self, suffix, data):
        for name in NAMES:
            (self.app / (name + suffix)).write_bytes(data)

    def test_linux_mixed_architecture_rejected(self):
        self.fill("", elf())
        release.verify_architecture(self.app, "linux", "amd64")
        (self.app / "multicnc").write_bytes(elf(183))
        with self.assertRaises(SystemExit):
            release.verify_architecture(self.app, "linux", "amd64")

    def test_missing_or_nonbinary_app_rejected(self):
        self.fill("", elf())
        (self.app / "multiphysics").write_text("not an executable")
        with self.assertRaises(SystemExit):
            release.verify_architecture(self.app, "linux", "amd64")

    def test_windows_rejects_32bit(self):
        self.fill(".exe", pe())
        release.verify_architecture(self.app, "windows", "amd64")
        (self.app / "multicnc.exe").write_bytes(pe(0x14c))
        with self.assertRaises(SystemExit):
            release.verify_architecture(self.app, "windows", "amd64")

    def test_armhf_requires_hard_float(self):
        for flags in (0, 0x05000200, 0x05000600, 0x04000400):
            self.fill("", elf(40, 1, flags))
            with self.assertRaises(SystemExit):
                release.verify_architecture(self.app, "linux", "armhf")

    def test_armhf_executable_without_optional_attributes(self):
        self.fill("", elf(40, 1, 0x05000400))
        with patch.object(release, "command", side_effect=AssertionError("ELF e_flags declares executable ABI")):
            release.verify_architecture(self.app, "linux", "armhf")

    def test_truncated_header_rejected(self):
        self.fill("", elf())
        (self.app / "multicnc").write_bytes(b"\x7fELF")
        with self.assertRaises(SystemExit):
            release.verify_architecture(self.app, "linux", "amd64")

    def test_hash_covers_all_bytes_and_changes_after_tamper(self):
        p = self.app / "payload"
        data = b"payload" * 200000
        p.write_bytes(data)
        digest = release.sha256(p)
        self.assertEqual(digest, hashlib.sha256(data).hexdigest())
        p.write_bytes(data + b"tampered")
        self.assertNotEqual(digest, release.sha256(p))


if __name__ == "__main__":
    unittest.main()
