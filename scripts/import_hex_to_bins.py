#!/usr/bin/env python3
import os, re, csv, json, hashlib, sys, time, zipfile
from pathlib import Path

try:
    from intelhex import IntelHex
except ImportError:
    print("Missing dependency: intelhex (pip install intelhex)", file=sys.stderr)
    sys.exit(2)

ROOT = Path(".").resolve()
IN_DIR  = ROOT / "dist" / "deepseek" / "output"       # hier legt DeepSeek seine HEX-Files ab
MAP_DIR = ROOT / "dist" / "deepseek" / "incoming"     # Sidecars + manifest vom Export
OUT_BIN = ROOT / "dist" / "processed" / "bins"
OUT_ZIP = ROOT / "dist" / "windows"
MANIFEST_ZIP = OUT_ZIP / "manifest-windows.csv"

def slug(s: str) -> str:
    s = (s or "").lower()
    s = re.sub(r"[ .()/\\]+", "-", s)
    s = re.sub(r"[^a-z0-9_-]", "", s)
    s = re.sub(r"-{2,}", "-", s).strip("-")
    return s or "na"

def sha256(p: Path) -> str:
    import hashlib
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024*1024), b""):
            h.update(chunk)
    return h.hexdigest()

def load_sidecar_for(hex_file: Path) -> dict:
    s = hex_file.with_suffix(".json")
    if s.exists():  # Sidecar direkt neben HEX (empfohlen)
        return json.loads(s.read_text(encoding="utf-8"))
    # sonst Sidecar im incoming/… suchen (gleicher Name)
    inc = (MAP_DIR / hex_file.name.replace(".hex",".json"))
    return json.loads(inc.read_text(encoding="utf-8")) if inc.exists() else {}

def package_zip(bin_path: Path, meta_rel: str, base_name: str, sha8: str):
    OUT_ZIP.mkdir(parents=True, exist_ok=True)
    zip_name = f"{base_name}-{sha8}.zip"
    zip_path = OUT_ZIP / zip_name
    readme = f"""ECUlibre Windows package
================================
Created: {time.strftime("%Y-%m-%d %H:%M:%S")}
Dataset: {base_name}
Bin SHA256 (full): {sha256(bin_path)}

Contents:
- {bin_path.name}
- metadata.yml (if present)

DISCLAIMER:
For research & educational purposes only. Respect local laws & safety regulations.
"""
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.write(bin_path, arcname=bin_path.name)
        if meta_rel and Path(meta_rel).exists():
            z.write(meta_rel, arcname="metadata.yml")
        z.writestr("README-WIN.txt", readme)
    return zip_path

def main():
    created = []
    if not IN_DIR.exists():
        print(f"No DeepSeek output dir: {IN_DIR}", file=sys.stderr)
        return 1

    for hex_file in IN_DIR.rglob("*.hex"):
        sc = load_sidecar_for(hex_file)
        base_addr = int(sc.get("base_addr", 0))
        meta_rel  = sc.get("meta_rel","")
        # Bau einen stabilen Basisnamen aus dem HEX-Dateinamen
        base = hex_file.stem  # enthält brand-model-…-sha8
        sha8 = base.split("-")[-1] if "-" in base else "unknown"

        # HEX -> BIN
        ih = IntelHex(str(hex_file))
        OUT_BIN.mkdir(parents=True, exist_ok=True)
        bin_out = OUT_BIN / f"{base}.bin"
        ih.tobinfile(str(bin_out))

        # ZIP
        zip_path = package_zip(bin_out, meta_rel, base, sha8)
        created.append((bin_out, zip_path, meta_rel))

    if not created:
        print("No .hex files found in DeepSeek output.", file=sys.stderr)
        return 0

    # Manifest
    MANIFEST_ZIP.parent.mkdir(parents=True, exist_ok=True)
    new = not MANIFEST_ZIP.exists()
    with MANIFEST_ZIP.open("a", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        if new: w.writerow(["zip","bin","meta_rel"])
        for bin_out, zip_path, meta_rel in created:
            w.writerow([str(zip_path.relative_to(ROOT)), str(bin_out.relative_to(ROOT)), meta_rel])

    print(f"Imported {len(created)} HEX → BIN and packaged ZIPs to {OUT_ZIP}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
