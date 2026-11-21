"""Testes offline para detecção de novas versões do MultiCNC."""
import io
import json
import unittest
from check_multicnc_release import is_newer, check


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self
    def __exit__(self, *args):
        self.close()


def fake_open(request, timeout):
    return FakeResponse(json.dumps({
        "tag_name": "v1.3.0", "html_url": "https://github.com/marcelomaurin/multicnc/releases/tag/v1.3.0",
        "assets": [{"name": "multicnc-setup.exe", "size": 1234,
                    "browser_download_url": "https://example.org/multicnc-setup.exe"}]
    }).encode())


class ReleaseTests(unittest.TestCase):
    def test_new_release(self):
        self.assertTrue(check("1.2.0", opener=fake_open)["update_available"])
    def test_equal_release(self):
        self.assertFalse(check("1.3.0", opener=fake_open)["update_available"])
    def test_older_release(self):
        self.assertFalse(check("1.4.0", opener=fake_open)["update_available"])
    def test_numeric_version(self):
        self.assertTrue(is_newer("1.9.0", "1.10.0"))
    def test_padding(self):
        self.assertFalse(is_newer("1.3", "1.3.0"))
    def test_invalid_tag(self):
        with self.assertRaises(ValueError):
            is_newer("1.0", "release-latest")
    def test_never_installs(self):
        self.assertFalse(check("1.2", opener=fake_open)["installation_performed"])


if __name__ == "__main__":
    unittest.main()
