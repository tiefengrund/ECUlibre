#!/usr/bin/env python3
import os, re, csv, json, hashlib, sys
from pathlib import Path

# Optional, aber empfohlen: pip install intelhex
try:
    from intelhex import IntelHex
except ImportError:
    print("Missing dependency: intelhex (pip install intelhex)", file=sys.stderr)
    sys.exit(2)

ROOT = Path(".").resolve()
OUTDIR = ROOT / "dist" / "deepseek" / "incoming"
MANIFEST = OUTDIR / "manifest-hex.csv"

def slug(s: str) -> str:
    s = (s or "").lower()
    s = re.sub(r"[ .()/\\]+", "-", s)
    s = re.sub(r"[^a-z0-9_-]", "", s)
    s = re.sub(r"-{2,}", "-", s).strip("-")
    return s or "na"

def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024*1024), b""):
            h.update(chunk)
    return h.hexdigest()

def read_meta(meta: Path) -> dict:
    d = {k:"" for k in ["brand","model","generation","ecu_vendor","ecu_model","firmware","region"]}
    if not meta.exists(): return d
    try:
        import yaml
        y = yaml.safe_load(meta.read_text(encoding="utf-8")) or {}
        for k in d: d[k] = str(y.get(k,"") or "")
        return d
    except Exception:
        # Minimal-Fallback: naive Zeilenparser
        for line in meta.read_text(encoding="utf-8", errors="ignore").splitlines():
            if ":" in line:
                k,v = line.split(":",1)
                k=k.strip(); v=v.strip().strip("'\"")
                if k in d: d[k]=v
        return d

def export_one(bin_path: Path, base_addr: int = 0):
    # Erwartete Struktur: rawdata/<Brand>/<Model>/<Gen>/<ECU>/<FW-REG>/validated/*.bin
    parts = bin_path.resolve().parts
    try:
        idx = parts.index("rawdata")
    except ValueError:
        return None
    # Ableitungen
    brand = parts[idx+1] if len(parts)>idx+1 else ""
    model = parts[idx+2] if len(parts)>idx+2 else ""
    gen   = parts[idx+3] if len(parts)>idx+3 else ""
    ecu   = parts[idx+4] if len(parts)>idx+4 else ""
    fwreg = parts[idx+5] if len(parts)>idx+5 else ""
    meta  = ROOT / Path(*parts[idx:idx+6]) / "metadata.yml"
    mi    = read_meta(meta)

    brand_s = slug(mi["brand"] or brand)
    model_s = slug(mi["model"] or model)
    gen_s   = slug(mi["generation"] or gen)
    ecu_s   = slug((mi["ecu_vendor"]+"-"+mi["ecu_model"]).strip("-") if (mi["ecu_vendor"] or mi["ecu_model"]) else ecu)
    fw_s    = slug(mi["firmware"] or fwreg.split("-")[0] if "-" in fwreg else fwreg)
    reg_s   = slug(mi["region"] or fwreg.split("-")[1] if "-" in fwreg else "")

    short = sha256(bin_path)[:8]
    base_name = "-".join([x for x in [brand_s,model_s,gen_s,ecu_s,fw_s,reg_s] if x]) or "dataset"
    rel_dir = OUTDIR / brand_s / model_s / gen_s / ecu_s / (fw_s + (f"-{reg_s}" if reg_s else ""))
    rel_dir.mkdir(parents=True, exist_ok=True)
    hex_name = f"{base_name}-{short}.hex"
    sidecar  = f"{base_name}-{short}.json"

    # BIN -> HEX
    data = bin_path.read_bytes()
    ih = IntelHex()
    ih.frombytes(data, offset=base_addr)
    ih.tofile(rel_dir / hex_name, format="hex")

    # Sidecar mit Mapping
    mapping = {
        "bin_rel": str(bin_path.relative_to(ROOT)),
        "meta_rel": str(meta.relative_to(ROOT)) if meta.exists() else "",
        "hex_rel": str((rel_dir / hex_name).relative_to(ROOT)),
        "base_addr": base_addr,
        "sha256_bin": sha256(bin_path),
    }
    (rel_dir / sidecar).write_text(json.dumps(mapping, indent=2), encoding="utf-8")

    return mapping

def main():
    created = []
    for p in ROOT.glob("rawdata/**/validated/*.bin"):
        m = export_one(p)
        if m: created.append(m)
    if not created:
        print("No .bin files under rawdata/**/validated/", file=sys.stderr)
        return 0
    # Manifest CSV
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    new = not MANIFEST.exists()
    with MANIFEST.open("a", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        if new: w.writerow(["hex_rel","bin_rel","meta_rel","base_addr","sha256_bin"])
        for m in created:
            w.writerow([m["hex_rel"], m["bin_rel"], m["meta_rel"], m["base_addr"], m["sha256_bin"]])
    print(f"Exported {len(created)} HEX files to {OUTDIR}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
