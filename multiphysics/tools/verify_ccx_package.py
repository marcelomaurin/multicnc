#!/usr/bin/env python3
"""Validação offline de pacote CalculiX antes da instalação (stdlib)."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import zipfile

def validate(zip_path: Path, expected_sha256: str) -> dict:
    if len(expected_sha256) != 64 or any(c not in "0123456789abcdef" for c in expected_sha256.lower()):
        raise ValueError("SHA-256 esperado inválido (64 caracteres hexadecimais obrigatórios)")
    digest = hashlib.sha256()
    with zip_path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    actual = digest.hexdigest()
    if actual != expected_sha256.lower():
        raise ValueError("SHA-256 divergente; pacote rejeitado")
    executables = []
    with zipfile.ZipFile(zip_path) as archive:
        entries = archive.infolist()
        if not entries:
            raise ValueError("ZIP vazio")
        if len(entries) > 20000:
            raise ValueError("ZIP com quantidade excessiva de entradas")
        total_size = 0
        for entry in entries:
            name = entry.filename.replace("\\", "/")
            path = PurePosixPath(name)
            if (not name or name.startswith("/") or
                    any(part == ".." for part in path.parts) or
                    ":" in path.parts[0] or "\x00" in name):
                raise ValueError("Caminho inseguro no ZIP: " + repr(name))
            # Symlinks Unix são rejeitados: não devem ser extraídos pelo instalador.
            mode = (entry.external_attr >> 16) & 0o170000
            if mode == 0o120000:
                raise ValueError("Link simbólico não permitido: " + name)
            total_size += entry.file_size
            if total_size > 2 * 1024**3:
                raise ValueError("ZIP excede limite de 2 GiB descompactados")
            if path.name.lower() == "ccx.exe":
                executables.append(name)
        if len(executables) != 1:
            raise ValueError("Esperado exatamente um ccx.exe, encontrados: " + str(len(executables)))
    return {"status": "VERIFICADO_PARA_INSPECAO", "sha256": actual,
            "ccx": executables[0], "entries": len(entries),
            "uncompressed_bytes": total_size,
            "warning": "Não homologado para instalação: faltam execução real, DLLs e licença."}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("zip", type=Path)
    parser.add_argument("--sha256", required=True, help="Hash confiável previamente homologado")
    args = parser.parse_args()
    try:
        print(json.dumps(validate(args.zip, args.sha256), ensure_ascii=False, indent=2))
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        print(json.dumps({"status": "REPROVADO", "erro": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
