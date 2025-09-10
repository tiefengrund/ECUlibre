cat > scripts/migrate_gen_paths.py <<'PY'
#!/usr/bin/env python3
import os, sys, re, subprocess, shutil, csv, pathlib, yaml

ROOT = pathlib.Path(".").resolve()
IDX_FILE = ROOT / "docs" / "vehicle-index.md"
MANIFEST = ROOT / "docs" / "vehicle-manifest.csv"
BRANDS_DIR = ROOT / "docs" / "brands"

def slug(s: str) -> str:
    s = (s or "").lower()
    s = re.sub(r"[ .()/\\]+", "-", s)
    s = re.sub(r"[^a-z0-9_-]", "", s)
    s = re.sub(r"-{2,}", "-", s).strip("-")
    return s or "na"

def git_mv(src: pathlib.Path, dst: pathlib.Path):
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(["git","mv","-k",str(src),str(dst)], check=True)
    except Exception:
        shutil.move(str(src), str(dst))

def rebuild_docs_from_manifest():
    if not MANIFEST.exists():
        print(f"[warn] manifest not found: {MANIFEST}", file=sys.stderr)
        return
    # Index neu schreiben
    lines = ["# Vehicle Index / Fahrzeug-Index\n",
             "| Brand | Model | Generation/Platform | Aliases | Path |\n",
             "|------:|:----- |:--------------------|:------- |:---- |\n"]
    # Brand-Seiten vorbereiten
    brand_tables = {}
    with MANIFEST.open("r", encoding="utf-8") as f:
        rdr = csv.DictReader(f)
        for row in rdr:
            brand = row["brand"]; model=row["model"]
            gen = row["generation_or_platform"]; aliases=row.get("aliases","")
            gen_slug = slug(gen)
            relpath = f"rawdata/{brand}/{model}/{gen_slug}"
            lines.append(f"| {brand} | {model} | {gen} | {aliases} | `{relpath}` |\n")
            bslug = slug(brand)
            brand_tables.setdefault(bslug, {"title":brand, "rows":[]})
            brand_tables[bslug]["rows"].append(f"| {model} | {gen} | {aliases} | `{relpath}` |\n")
    IDX = "".join(lines)
    IDX_FILE.write_text(IDX, encoding="utf-8")
    BRANDS_DIR.mkdir(parents=True, exist_ok=True)
    for bslug, data in brand_tables.items():
        bdir = BRANDS_DIR / bslug
        bdir.mkdir(parents=True, exist_ok=True)
        md = f"# {data['title']}\n\n| Model | Generation/Platform | Aliases | Path |\n|:----- |:--------------------|:------- |:---- |\n" + "".join(sorted(set(data["rows"])))
        (bdir / "README.md").write_text(md, encoding="utf-8")

def main():
    moved = 0
    for mpath in ROOT.glob("rawdata/**/metadata.yml"):
        parts = mpath.resolve().parts
        try:
            i = parts.index("rawdata")
        except ValueError:
            continue
        # parts: rawdata / BRAND / MODEL / <gen...maybe multi> / ECU / FW / metadata.yml
        if len(parts) < i+6:
            continue
        brand = parts[i+1]; model = parts[i+2]
        ecu   = parts[-3]; fw = parts[-2]  # metadata.yml unter FW
        gen_parts = parts[i+3:-3]
        # generation aus YAML (falls vorhanden), sonst aus gen_parts joinen
        try:
            data = yaml.safe_load(mpath.read_text(encoding="utf-8")) or {}
            gen_text = str(data.get("generation","") or " ".join(gen_parts))
        except Exception:
            gen_text = " ".join(gen_parts)
        gen_s = slug(gen_text)
        # Zielpfad
        dst_fw = ROOT / "rawdata" / brand / model / gen_s / ecu / fw
        cur_fw = mpath.parent
        if cur_fw.resolve() == dst_fw.resolve():
            continue
        print(f"move: {cur_fw} -> {dst_fw}")
        dst_fw.parent.mkdir(parents=True, exist_ok=True)
        git_mv(cur_fw, dst_fw)
        moved += 1

        # optional: workbench spiegeln
        wb_cur = ROOT / "workbench" / brand / model / "/".join(gen_parts) / ecu / fw
        wb_dst = ROOT / "workbench" / brand / model / gen_s / ecu / fw
        # normalize Path objects
        wb_cur = pathlib.Path(str(wb_cur).replace("//","/"))
        wb_dst = pathlib.Path(str(wb_dst).replace("//","/"))
        if wb_cur.exists() and wb_cur.resolve() != wb_dst.resolve():
            print(f"move(workbench): {wb_cur} -> {wb_dst}")
            wb_dst.parent.mkdir(parents=True, exist_ok=True)
            try:
                subprocess.run(["git","mv","-k",str(wb_cur),str(wb_dst)], check=True)
            except Exception:
                shutil.move(str(wb_cur), str(wb_dst))

    rebuild_docs_from_manifest()
    print(f"done. moved FW dirs: {moved}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
PY
