#!/usr/bin/env python3
"""Consulta a versão publicada em GitHub Releases; não instala nada."""
import argparse
import json
import re
import urllib.error
import urllib.request

API = "https://api.github.com/repos/marcelomaurin/multicnc/releases/latest"
VERSION = re.compile(r"^v?(\d+(?:\.\d+)*)(?:[-+].*)?$", re.I)


def numbers(tag):
    match = VERSION.fullmatch(tag.strip())
    if not match:
        raise ValueError("Versão inválida: " + tag)
    return tuple(int(part) for part in match.group(1).split("."))


def is_newer(current, published):
    a, b = numbers(current), numbers(published)
    width = max(len(a), len(b))
    return a + (0,) * (width - len(a)) < b + (0,) * (width - len(b))


def check(current, url=API, opener=urllib.request.urlopen):
    request = urllib.request.Request(
        url, headers={"Accept": "application/vnd.github+json",
                      "User-Agent": "MultiCNC-Update-Check"})
    with opener(request, timeout=15) as response:
        release = json.load(response)
    tag = release["tag_name"]
    assets = [{"name": a["name"], "size": a.get("size"),
               "url": a["browser_download_url"]}
              for a in release.get("assets", [])
              if a.get("browser_download_url", "").startswith("https://")]
    return {"current": current, "latest": tag,
            "update_available": is_newer(current, tag),
            "assets": assets, "release_url": release.get("html_url"),
            "installation_performed": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--current", required=True, help="Versão instalada, ex.: 0.2.0")
    args = parser.parse_args()
    try:
        result = check(args.current)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (ValueError, KeyError, urllib.error.URLError, TimeoutError, OSError) as exc:
        print(json.dumps({"status": "ERROR", "message": str(exc)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
