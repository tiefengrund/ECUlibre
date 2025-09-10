#!/usr/bin/env python3
import os, re, csv, hashlib, sys, json
from pathlib import Path
from intelhex import IntelHex

ROOT = Path(".").resolve()
OUTDIR = ROOT / "dist" / "deepseek" / "incoming"
MANIFEST = OUTDIR / "manifest-hex.csv"

def slug(s:str)->str:
    s=(s or "").lower()
    s=re.sub(r"[ .()/\\]+","-",s); s=re.sub(r"[^a-z0-9_-]","",s)
    s=re.sub(r"-{2,}","-",s).strip("-")
    return s or "na"

def sha256(p:Path)->str:
    h=hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda:f.read(1<<20), b""): h.update(chunk)
    return h.hexdigest()

def tiny_meta(meta:Path):
    d={k:"" for k in ["brand","model","generation","ecu_vendor","ecu_model","firmware","region"]}
    if meta.exists():
        try:
            import yaml
            y=yaml.safe_load(meta.read_text(encoding="utf-8")) or {}
            for k in d: d[k]=str(y.get(k,"") or "")
        except Exception:
            pass
    return d

def export_bin(b:Path, base:int=0):
    parts=b.resolve().parts
    try: i=parts.index("rawdata")
    except ValueError: return None
    brand=parts[i+1] if len(parts)>i+1 else ""
    model=parts[i+2] if len(parts)>i+2 else ""
    gen  =parts[i+3] if len(parts)>i+3 else ""
    ecu  =parts[i+4] if len(parts)>i+4 else ""
    fwreg=parts[i+5] if len(parts)>i+5 else ""
    meta =ROOT.joinpath(*parts[i:i+6], "metadata.yml")

    mi=tiny_meta(Path(meta))
    brand_s=slug(mi["brand"] or brand); model_s=slug(mi["model"] or model)
    gen_s=slug(mi["generation"] or gen)
    ecu_s=slug((mi["ecu_vendor"]+"-"+mi["ecu_model"]).strip("-") if (mi["ecu_vendor"] or mi["ecu_model"]) else ecu)
    fw_s=slug(mi["firmware"] or (fwreg.split("-")[0] if "-" in fwreg else fwreg))
    reg_s=slug(mi["region"]   or (fwreg.split("-")[1] if "-" in fwreg else ""))

    short=sha256(b)[:8]
    base_name="-".join([x for x in [brand_s,model_s,gen_s,ecu_s,fw_s,reg_s] if x]) or "dataset"

    outdir=OUTDIR/brand_s/model_s/gen_s/ecu_s/(fw_s + (f"-{reg_s}" if reg_s else ""))
    outdir.mkdir(parents=True, exist_ok=True)
    hex_path=outdir/f"{base_name}-{short}.hex"
    sidecar =outdir/f"{base_name}-{short}.json"

    data=b.read_bytes()
    ih=IntelHex(); ih.frombytes(data, offset=base); ih.tofile(hex_path, format="hex")

    sidecar.write_text(json.dumps({
        "bin_rel": str(b.relative_to(ROOT)),
        "meta_rel": str(Path(meta).relative_to(ROOT)) if Path(meta).exists() else "",
        "hex_rel": str(hex_path.relative_to(ROOT)),
        "base_addr": base,
        "sha256_bin": sha256(b),
    }, indent=2), encoding="utf-8")
    return hex_path

def main():
    created=[]
    for p in ROOT.glob("rawdata/**/validated/*.bin"):
        hp=export_bin(p)
        if hp: created.append(hp)
    if not created:
        print("No .bin under rawdata/**/validated/", file=sys.stderr)
        return 0

    OUTDIR.mkdir(parents=True, exist_ok=True)
    new=not MANIFEST.exists()
    with MANIFEST.open("a", newline="", encoding="utf-8") as f:
        w=csv.writer(f)
        if new: w.writerow(["hex_rel","bin_rel","meta_rel","base_addr","sha256_bin"])
        for sc in sorted(OUTDIR.rglob("*.json")):
            j=json.loads(sc.read_text(encoding="utf-8"))
            w.writerow([j["hex_rel"], j["bin_rel"], j.get("meta_rel",""), j.get("base_addr",0), j["sha256_bin"]])
    print(f"Exported {len(created)} HEX files → {OUTDIR}")
    return 0

if __name__=="__main__": sys.exit(main())
