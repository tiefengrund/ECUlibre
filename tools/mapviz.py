#!/usr/bin/env python3
"""
Minimaler ECU-Reporter/Visualizer:
- findet .bin-Dateien (glob)
- optional lädt Maps aus YAML-Specs
- erzeugt Histogramm + Markdown-Report (+ CSV je Map)
"""
import argparse, glob, os, pathlib, re, sys, json, math, hashlib
from typing import Dict, Any, List
import numpy as np
import yaml
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

DTYPES = {"u8": np.uint8, "s8": np.int8, "u16": np.uint16, "s16": np.int16,
          "u32": np.uint32, "s32": np.int32, "f32": np.float32}
ENDIANS = {"little": "<", "big": ">"}

def to_int(x): 
    return int(x,16) if isinstance(x,str) and x.lower().startswith("0x") else int(x)

def load_specs(patterns: List[str]) -> List[Dict[str, Any]]:
    files=[]
    for pat in patterns: files.extend(glob.glob(pat, recursive=True))
    specs=[]
    for p in files:
        try:
            with open(p,"r",encoding="utf-8") as f:
                specs.append(yaml.safe_load(f) or {})
        except Exception as e:
            print(f"[spec] skip {p}: {e}", file=sys.stderr)
    return specs

def index_deepseek(patterns: List[str]) -> Dict[str, Dict[str, Any]]:
    files=[]
    for pat in patterns: files.extend(glob.glob(pat, recursive=True))
    idx={}
    for p in files:
        try:
            with open(p,"r",encoding="utf-8") as f:
                obj=json.load(f)
            if isinstance(obj, dict) and "maps" in obj:
                maps = obj["maps"]
            elif isinstance(obj, list):
                maps = obj
            else:
                maps = [obj]
            for m in maps:
                name = str(m.get("name") or m.get("map") or pathlib.Path(p).stem)
                vals = m.get("values") or m.get("data")
                if vals is None: continue
                arr = np.array(vals, dtype=float)
                # optional reshape
                rows, cols = m.get("rows") or m.get("height"), m.get("cols") or m.get("width")
                if rows and cols:
                    try: arr = arr.reshape((int(rows), int(cols)))
                    except Exception: pass
                idx[name] = {"array": arr, "source": p}
        except Exception as e:
            print(f"[deepseek] skip {p}: {e}", file=sys.stderr)
    return idx

def mesh_axes(m, rows, cols):
    def axbuild(axspec, count):
        if not axspec: return np.arange(count, dtype=float)
        if "values" in axspec:
            vals = np.array(axspec["values"], dtype=float)
            if len(vals) != count: vals = np.resize(vals, (count,))
            return vals
        start = float(axspec.get("start", 0.0)); step = float(axspec.get("step", 1.0))
        return start + step*np.arange(count, dtype=float)
    X = axbuild(m.get("x_axis"), cols); Y = axbuild(m.get("y_axis"), rows)
    return np.meshgrid(X, Y)

def read_map_from_bin(bin_path, m):
    off = to_int(m["offset"]); rows = int(m["rows"]); cols = int(m["cols"])
    dtype = m.get("dtype","u16"); endian=m.get("endian","little")
    scale=float(m.get("scale",1.0)); add=float(m.get("add",0.0))
    if dtype not in DTYPES or endian not in ENDIANS: raise ValueError("bad dtype/endian")
    bsize = np.dtype(DTYPES[dtype]).itemsize; need = rows*cols*bsize
    with open(bin_path, "rb") as f:
        f.seek(off); buf=f.read(need)
        if len(buf)<need: raise ValueError(f"Not enough bytes at 0x{off:X} need {need} got {len(buf)}")
        arr = np.frombuffer(buf, dtype=np.dtype(ENDIANS[endian]+DTYPES[dtype].name))
        arr = arr.reshape((rows, cols)).astype(float)
        return arr*scale + add

def byte_histogram(data: bytes, png: str):
    arr = np.frombuffer(data, dtype=np.uint8)
    hist, _ = np.histogram(arr, bins=256, range=(0,256))
    fig = plt.figure(figsize=(10,4)); ax = fig.add_subplot(111)
    ax.bar(np.arange(256), hist, width=1.0)
    ax.set_title("Byte histogram"); ax.set_xlabel("byte"); ax.set_ylabel("count")
    fig.tight_layout(); fig.savefig(png, dpi=150); plt.close(fig)

def analyze_file(bin_path: str, outdir: str):
    dat = pathlib.Path(bin_path).read_bytes()
    sha = hashlib.sha256(dat).hexdigest()
    png_hist = os.path.join(outdir, "histogram.png")
    byte_histogram(dat, png_hist)
    # simple strings
    s_out=[]; cur=[]
    for b in dat:
        if 32 <= b <= 126: cur.append(chr(b))
        else:
            if len(cur)>=6: s_out.append("".join(cur))
            cur=[]
    if len(cur)>=6: s_out.append("".join(cur))
    return {
        "path": bin_path, "size": len(dat), "sha256": sha,
        "hist_png": os.path.relpath(png_hist),
        "strings": s_out[:40],
    }

def save_csv(path, X, Y, Z):
    with open(path,"w",encoding="utf-8") as f:
        f.write("y\\x," + ",".join(map(str, X[0].tolist())) + "\n")
        for r in range(Z.shape[0]):
            f.write(str(Y[r,0]) + "," + ",".join(f"{v:.6g}" for v in Z[r,:]) + "\n")

def surface_pair(outpng, title, X, Y, Zbin, Zds=None):
    if Zds is not None and Zds.shape != Zbin.shape: Zds=None
    if Zds is None:
        fig = plt.figure(figsize=(9,7)); ax = fig.add_subplot(111, projection="3d")
        ax.plot_surface(X, Y, Zbin, cmap="viridis", linewidth=0, antialiased=True)
        ax.set_title(title + " (BIN)")
    else:
        fig = plt.figure(figsize=(16,7))
        ax1 = fig.add_subplot(121, projection="3d"); ax2 = fig.add_subplot(122, projection="3d")
        ax1.plot_surface(X, Y, Zbin, cmap="viridis", linewidth=0, antialiased=True); ax1.set_title(title + " (BIN)")
        ax2.plot_surface(X, Y, Zds, cmap="plasma", linewidth=0, antialiased=True); ax2.set_title(title + " (DeepSeek)")
    for ax in fig.axes:
        try: ax.set_xlabel("X"); ax.set_ylabel("Y"); ax.set_zlabel("Z")
        except Exception: pass
    fig.tight_layout(); fig.savefig(outpng, dpi=200); plt.close(fig)

def main():
    ap = argparse.ArgumentParser(description="ECU map visualize/analyze")
    ap.add_argument("--bins", default="rawdata/**/*.bin")
    ap.add_argument("--specs", default="mapspecs/**/*.y?(a)ml")
    ap.add_argument("--deepseek", default="deepseek/maps/**/*.json")
    ap.add_argument("--outdir", default="out/mapviz")
    a = ap.parse_args()

    bin_paths = glob.glob(a.bins, recursive=True)
    specs = load_specs([a.specs])
    ds_idx = index_deepseek([a.deepseek])

    pathlib.Path(a.outdir).mkdir(parents=True, exist_ok=True)
    index_lines = ["# Index", ""]
    for binp in bin_paths:
        base = pathlib.Path(binp).name
        dst = pathlib.Path(a.outdir) / pathlib.Path(base).with_suffix("")
        dst.mkdir(parents=True, exist_ok=True)

        info = analyze_file(binp, str(dst))
        md = [f"# Report for `{base}`", "",
              "## File", f"- Path: `{info['path']}`",
              f"- Size: `{info['size']}` bytes",
              f"- SHA256: `{info['sha256']}`", "",
              "### Histogram", f"![histogram]({info['hist_png']})", ""]
        if info["strings"]:
            md.append("### Strings (first 40)")
            md += [f"- `{s.replace('|','\\|')}`" for s in info["strings"]]
            md.append("")

        # flatten spec maps
        all_maps=[m for spec in specs for m in (spec.get("maps") or [])]
        if all_maps:
            md.append("## Maps")
            for m in all_maps:
                name = str(m.get("name","<unnamed>"))
                safe = re.sub(r'[^a-zA-Z0-9_.-]+', '_', name)
                try:
                    Zbin = read_map_from_bin(binp, m)
                except Exception as e:
                    md.append(f"### {name}\n- ⚠️ {e}\n"); continue
                rows, cols = Zbin.shape
                X, Y = mesh_axes(m, rows, cols)
                Zds = None
                if name in ds_idx:
                    try:
                        z = np.array(ds_idx[name]["array"], dtype=float)
                        if z.shape == Zbin.shape: Zds = z
                    except Exception: pass
                png_pair = os.path.join(dst, f"{safe}.pair.png")
                surface_pair(str(png_pair), name, X, Y, Zbin, Zds)
                csv_path = os.path.join(dst, f"{safe}.csv")
                save_csv(str(csv_path), X, Y, Zbin)
                md += [f"### {name}", "",
                       f"[CSV]({os.path.relpath(csv_path)})  ",
                       f"![{name}]({os.path.relpath(png_pair)})", ""]
        rep = os.path.join(dst, "REPORT.md")
        with open(rep, "w", encoding="utf-8") as f: f.write("\n".join(md) + "\n")
        index_lines.append(f"- [{base}]({os.path.relpath(rep, a.outdir)})")

    with open(os.path.join(a.outdir, "INDEX.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(index_lines) + "\n")

if __name__ == "__main__":
    main()
