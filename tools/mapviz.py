#!/usr/bin/env python3
"""
ECU Map Visualizer / Analyzer

Features:
- Dark-Theme 3D surface (wireframe + red support points) + heatmap table with numbers
- Spec-based rendering from YAML mapspecs
- Optional DeepSeek overlay (if JSON provided, shape-compatible)
- CSV export per map, REPORT.md per BIN, top-level INDEX.md
- Autodiscovery mode (if no specs): scan u16/s16, little/big, common shapes and render top candidates

Usage (defaults):
  python tools/mapviz.py --bins "rawdata/**/*.bin" --specs "mapspecs/**/*.y?(a)ml" \
                         --deepseek "deepseek/maps/**/*.json" --outdir "out/mapviz"

Autodiscovery:
  python tools/mapviz.py --autodiscover --bins "rawdata/**/*.bin" --outdir "out/auto"

If no specs are found AND --autodiscover is not given, autodiscovery kicks in automatically.
"""

import argparse, json, os, sys, glob, hashlib, math, pathlib, re
from typing import Dict, Any, List, Tuple, Optional

import numpy as np
import yaml
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


# ---------------- THEME ----------------

def apply_dark_theme():
    import matplotlib as mpl
    plt.style.use("dark_background")
    mpl.rcParams.update({
        "figure.facecolor": "#000000",
        "axes.facecolor":   "#000000",
        "savefig.facecolor":"#000000",
        "axes.edgecolor":   "#808080",
        "axes.labelcolor":  "#e0e0e0",
        "xtick.color":      "#c8c8c8",
        "ytick.color":      "#c8c8c8",
        "grid.color":       "#444444",
        "font.size":        10,
        "legend.frameon":   False,
    })


# ---------------- UTILS ----------------

DTYPES = {
    "u8": np.uint8, "s8": np.int8,
    "u16": np.uint16, "s16": np.int16,
    "u32": np.uint32, "s32": np.int32,
    "f32": np.float32,
}
ENDIANS = {"little": "<", "big": ">"}

def to_int(x):
    if isinstance(x, int): return x
    if isinstance(x, str) and x.lower().startswith("0x"): return int(x, 16)
    return int(x)

def sha256_path(p)->str:
    h=hashlib.sha256()
    with open(p,"rb") as f:
        for chunk in iter(lambda: f.read(1<<20), b""):
            h.update(chunk)
    return h.hexdigest()

def shannon_entropy(data: bytes) -> float:
    if not data: return 0.0
    from collections import Counter
    c = Counter(data); n = len(data)
    return -sum((cnt/n)*math.log2(cnt/n) for cnt in c.values())

def find_strings(data: bytes, minlen=6, limit=40) -> List[str]:
    out=[]; cur=[]
    for b in data:
        if 32 <= b <= 126:    # printable
            cur.append(chr(b))
        else:
            if len(cur) >= minlen:
                out.append("".join(cur))
                if len(out) >= limit: break
            cur=[]
    if len(cur) >= minlen and len(out) < limit:
        out.append("".join(cur))
    return out

def load_specs(patterns: List[str]) -> List[Dict[str, Any]]:
    files=[]
    for pat in patterns: files.extend(glob.glob(pat, recursive=True))
    specs=[]
    for p in files:
        try:
            with open(p,"r",encoding="utf-8") as f:
                obj = yaml.safe_load(f)
                if obj: specs.append(obj)
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
            maps=[]
            if isinstance(obj, dict) and "maps" in obj:
                maps = obj["maps"]
            elif isinstance(obj, dict) and ("values" in obj or "data" in obj):
                maps = [obj]
            elif isinstance(obj, list):
                maps = obj
            for m in maps:
                name = str(m.get("name") or m.get("map") or pathlib.Path(p).stem)
                vals = m.get("values") or m.get("data")
                rows = m.get("rows") or m.get("height")
                cols = m.get("cols") or m.get("width")
                if vals is None: continue
                arr = np.array(vals, dtype=np.float64)
                if rows and cols:
                    try: arr = arr.reshape((int(rows), int(cols)))
                    except Exception: pass
                idx[name] = {"array": arr, "source": p}
        except Exception as e:
            print(f"[deepseek] skip {p}: {e}", file=sys.stderr)
    return idx

def mesh_axes(spec_map, rows, cols):
    def axbuild(axspec, count):
        if not axspec: return np.arange(count, dtype=np.float64)
        if "values" in axspec:
            vals = np.array(axspec["values"], dtype=np.float64)
            if len(vals) != count:
                vals = np.resize(vals, (count,))
            return vals
        start = float(axspec.get("start", 0.0))
        step  = float(axspec.get("step", 1.0))
        return start + step*np.arange(count, dtype=np.float64)
    X = axbuild(spec_map.get("x_axis"), cols)
    Y = axbuild(spec_map.get("y_axis"), rows)
    XX, YY = np.meshgrid(X, Y)
    return XX, YY

def read_map_from_bin(bin_path, m: Dict[str,Any]) -> np.ndarray:
    off = to_int(m["offset"])
    rows = int(m["rows"]); cols = int(m["cols"])
    dtype = m.get("dtype","u16"); endian=m.get("endian","little")
    scale=float(m.get("scale",1.0)); add=float(m.get("add",0.0))
    if dtype not in DTYPES: raise ValueError(f"Unknown dtype {dtype}")
    if endian not in ENDIANS: raise ValueError(f"Unknown endian {endian}")
    bsize = np.dtype(DTYPES[dtype]).itemsize
    need = rows*cols*bsize
    with open(bin_path, "rb") as f:
        f.seek(off)
        buf=f.read(need)
        if len(buf)<need: raise ValueError(f"Not enough bytes at 0x{off:X} need {need} got {len(buf)}")
        dt = np.dtype(DTYPES[dtype]).newbyteorder(ENDIANS[endian])  # '<' oder '>'
        arr = np.frombuffer(buf, dtype=dt)
        arr = arr.reshape((rows, cols)).astype(np.float64)
        arr = arr*scale + add
        return arr

def save_csv(path, X, Y, Z):
    with open(path,"w",encoding="utf-8") as f:
        f.write("y\\x," + ",".join(map(str, X[0].tolist())) + "\n")
        for r in range(Z.shape[0]):
            f.write(str(Y[r,0]) + "," + ",".join(f"{v:.6g}" for v in Z[r,:]) + "\n")


# ---------------- RENDERING ----------------

def surface_pair(outpng, title, X, Y, Zbin, Zds=None):
    """Dark 3D surface with wireframe + red support points, optional comparison."""
    from mpl_toolkits.mplot3d import Axes3D  # noqa: F401
    apply_dark_theme()
    cmap1 = "turbo"
    cmap2 = "plasma"

    def _surface(ax, X, Y, Z, label, cmap):
        surf = ax.plot_surface(X, Y, Z, cmap=cmap, linewidth=0, antialiased=True, alpha=0.95, shade=True)
        # wireframe (sparser)
        rstep = max(1, int(max(1, X.shape[0]//8)))
        cstep = max(1, int(max(1, X.shape[1]//8)))
        ax.plot_wireframe(X, Y, Z, rstride=rstep, cstride=cstep, color=(1,1,1,0.15), linewidth=0.6)
        # red points
        ax.scatter(X, Y, Z, c="#ff3b3b", s=8, depthshade=False)
        # ground contours
        ax.contour(X, Y, Z, zdir='z', offset=float(np.nanmin(Z)), cmap="Greys", linewidths=0.6, alpha=0.8)
        ax.set_title(label, pad=12)
        ax.set_xlabel("Engine Speed [rpm]")
        ax.set_ylabel("Inlet Manifold Pressure [kPa]")
        ax.set_zlabel("[%]")
        for pane in [ax.w_xaxis, ax.w_yaxis, ax.w_zaxis]:
            try:
                pane.set_pane_color((0,0,0,0.0))
            except Exception:
                pass
        ax.grid(True, linestyle=":", alpha=0.5)
        return surf

    if Zds is None:
        fig = plt.figure(figsize=(11,8), facecolor="#000")
        ax = fig.add_subplot(111, projection="3d")
        _surface(ax, X, Y, Zbin, title + " (BIN)", cmap1)
        fig.tight_layout()
        fig.savefig(outpng, dpi=220, bbox_inches="tight")
        plt.close(fig)
    else:
        fig = plt.figure(figsize=(18,8), facecolor="#000")
        ax1 = fig.add_subplot(121, projection="3d")
        ax2 = fig.add_subplot(122, projection="3d")
        _surface(ax1, X, Y, Zbin, title + " (BIN)", cmap1)
        _surface(ax2, X, Y, Zds,  title + " (DeepSeek)", cmap2)
        fig.tight_layout()
        fig.savefig(outpng, dpi=220, bbox_inches="tight")
        plt.close(fig)

def heatmap_table_png(png_path, X, Y, Z):
    """Color table with numeric labels."""
    apply_dark_theme()
    fig = plt.figure(figsize=(14,5), facecolor="#000")
    ax = fig.add_subplot(111)
    im = ax.imshow(Z, aspect="auto", cmap="turbo", origin="upper")
    # ticks (sparse if many)
    max_ticks = 16
    x_idx = np.linspace(0, Z.shape[1]-1, min(Z.shape[1], max_ticks), dtype=int)
    y_idx = np.linspace(0, Z.shape[0]-1, min(Z.shape[0], max_ticks), dtype=int)
    ax.set_xticks(x_idx, [f"{X[0,i]:.0f}" for i in x_idx], rotation=0)
    ax.set_yticks(y_idx, [f"{Y[i,0]:.0f}" for i in y_idx])

    # numeric labels (subsample on big tables)
    step_r = 1 if Z.shape[0] <= 20 else int(np.ceil(Z.shape[0]/20))
    step_c = 1 if Z.shape[1] <= 20 else int(np.ceil(Z.shape[1]/20))
    mean = float(np.nanmean(Z))
    for r in range(0, Z.shape[0], step_r):
        for c in range(0, Z.shape[1], step_c):
            color = "#000" if Z[r,c] < mean else "#fff"
            ax.text(c, r, f"{Z[r,c]:.1f}", ha="center", va="center", fontsize=7, color=color)

    ax.set_xlabel("Engine Speed [rpm]")
    ax.set_ylabel("Inlet Manifold Pressure [kPa]")
    ax.grid(False)
    fig.colorbar(im, ax=ax, fraction=0.02, pad=0.02)
    fig.tight_layout()
    fig.savefig(png_path, dpi=220, bbox_inches="tight")
    plt.close(fig)


# ---------------- ANALYZE / REPORT ----------------

def read_metadata_for_bin(bin_path: str) -> Dict[str,str]:
    p = pathlib.Path(bin_path).resolve()
    for parent in [p.parent] + list(p.parents):
        cand = parent / "metadata.yml"
        if cand.exists():
            try:
                with open(cand,"r",encoding="utf-8") as f:
                    y = yaml.safe_load(f) or {}
                keep = {k:str(v) for k,v in y.items() if k in ("brand","model","generation","ecu_vendor","ecu_model","firmware","region","schema_version")}
                return keep
            except Exception:
                pass
    return {}

def analyze_bin(bin_path: str, outdir: str):
    dat = pathlib.Path(bin_path).read_bytes()
    info = {
        "path": str(bin_path),
        "size_bytes": len(dat),
        "sha256": sha256_path(bin_path),
        "entropy_bits_per_byte": round(shannon_entropy(dat), 4),
        "pct_zero": round(100.0*dat.count(0)/max(1,len(dat)), 3),
    }
    png_hist = os.path.join(outdir, "histogram.png")

    # histogram
    arr = np.frombuffer(dat, dtype=np.uint8)
    hist, _ = np.histogram(arr, bins=256, range=(0,256))
    apply_dark_theme()
    fig = plt.figure(figsize=(10,4), facecolor="#000")
    ax = fig.add_subplot(111)
    ax.bar(np.arange(256), hist, width=1.0)
    ax.set_title("Byte histogram"); ax.set_xlabel("byte"); ax.set_ylabel("count")
    fig.tight_layout(); fig.savefig(png_hist, dpi=150, bbox_inches="tight"); plt.close(fig)

    # strings
    strings = find_strings(dat, minlen=6, limit=40)
    return info, strings, os.path.relpath(png_hist)

def render_report(bin_path: str, out_dir: str, maps: List[Dict[str,Any]], ds_idx: Dict[str,Dict[str,Any]]):
    os.makedirs(out_dir, exist_ok=True)
    info, strings, hist_rel = analyze_bin(bin_path, out_dir)

    md = []
    md.append(f"# Report for `{os.path.basename(bin_path)}`")
    md.append("")
    md.append("## File Info")
    md.append("")
    meta = read_metadata_for_bin(bin_path)
    if meta:
        md.append("**Metadata (from metadata.yml):**  " + ", ".join([f"{k}={v}" for k,v in meta.items()]))
    md += [
        f"- Path: `{info['path']}`",
        f"- Size: `{info['size_bytes']}` bytes",
        f"- SHA256: `{info['sha256']}`",
        f"- Shannon entropy: `{info['entropy_bits_per_byte']}` bits/byte",
        f"- Zero bytes: `{info['pct_zero']}%`",
        "",
        "### Byte histogram",
        f"![histogram]({hist_rel})",
        ""
    ]
    if strings:
        md.append("### Top printable strings (first 40)")
        for s in strings:
            s = s.replace("|","\\|")
            md.append(f"- `{s}`")
        md.append("")

    if not maps:
        md.append("> No maps found from specs.")
    else:
        md.append("## Maps")
        for m in maps:
            name = str(m.get("name","<unnamed>"))
            safe = re.sub(r'[^a-zA-Z0-9_.-]+', '_', name)
            try:
                Zbin = read_map_from_bin(bin_path, m)
            except Exception as e:
                md.append(f"### {name}\n- ⚠️ {e}\n")
                continue
            rows, cols = Zbin.shape
            X, Y = mesh_axes(m, rows, cols)

            # DeepSeek overlay if compatible
            Zds = None
            if name in ds_idx:
                try:
                    zc = np.array(ds_idx[name]["array"], dtype=float)
                    if zc.shape == Zbin.shape:
                        Zds = zc
                except Exception:
                    pass

            # outputs
            png_pair = os.path.join(out_dir, f"{safe}.pair.png")
            surface_pair(png_pair, name, X, Y, Zbin, Zds)
            csv_path = os.path.join(out_dir, f"{safe}.csv")
            save_csv(csv_path, X, Y, Zbin)
            png_heat = os.path.join(out_dir, f"{safe}.heatmap.png")
            heatmap_table_png(png_heat, X, Y, Zbin)

            md.append(f"### {name}")
            md.append("")
            md.append(f"**Offset:** `0x{to_int(m['offset']):X}`, **shape:** `{rows}×{cols}`, **dtype:** `{m.get('dtype','u16')}`, **endian:** `{m.get('endian','little')}`  ")
            md.append(f"[CSV]({os.path.relpath(csv_path)})  ")
            md.append(f"![{name}]({os.path.relpath(png_pair)})")
            md.append(f"![{name} table]({os.path.relpath(png_heat)})")
            md.append("")

            if Zds is not None:
                png_diff = os.path.join(out_dir, f"{safe}.diff.png")
                # simple diff rendering
                D = Zds - Zbin
                apply_dark_theme()
                fig = plt.figure(figsize=(8,7), facecolor="#000")
                ax = fig.add_subplot(111, projection="3d")
                ax.plot_surface(X, Y, D, cmap="coolwarm", linewidth=0, antialiased=True)
                ax.set_title(name + " (DeepSeek - BIN)")
                ax.set_xlabel("X"); ax.set_ylabel("Y"); ax.set_zlabel("ΔZ")
                fig.tight_layout(); fig.savefig(png_diff, dpi=200, bbox_inches="tight"); plt.close(fig)
                md.append(f"**Diff (DeepSeek − BIN):**")
                md.append(f"![{name} diff]({os.path.relpath(png_diff)})")
                md.append("")

    rep = os.path.join(out_dir, "REPORT.md")
    with open(rep, "w", encoding="utf-8") as f:
        f.write("\n".join(md) + "\n")
    return rep


# ---------------- AUTODISCOVERY ----------------

def scan_autotables(bin_bytes: bytes,
                    shapes=((16,16),(12,16),(16,20),(10,16),(8,16)),
                    dtypes=("u16","s16"),
                    endians=("little","big"),
                    stride_align=2,
                    topk=6):
    H=[]
    n = len(bin_bytes)
    for dtype in dtypes:
        npdt = np.uint16 if dtype=="u16" else np.int16
        itemsize = np.dtype(npdt).itemsize
        for endian in endians:
            code = ("<" if endian=="little" else ">") + ("u2" if dtype=="u16" else "i2")
            arr = np.frombuffer(bin_bytes, dtype=np.dtype(code))
            for rows, cols in shapes:
                block_items = rows*cols
                if len(arr) < block_items: continue
                step = max(1, stride_align//itemsize)
                # stride: lightweight window
                for i in range(0, len(arr)-block_items, step):
                    view = arr[i:i+block_items]
                    Z = view.astype(np.float64).reshape((rows,cols))
                    rng = float(Z.max()-Z.min())
                    if not (5.0 <= rng <= 10000.0):
                        continue
                    gy, gx = np.gradient(Z)
                    lap = float((gx**2 + gy**2).mean())
                    mono = float(np.mean(np.diff(Z, axis=1) >= 0) + np.mean(np.diff(Z, axis=0) >= 0))
                    score = lap - 0.1*mono   # lower is better
                    H.append((score, i*itemsize, rows, cols, dtype, endian))
    H.sort(key=lambda x: x[0])
    return H[:topk]

def autodiscover_for_bin(bin_path: str, outdir: str):
    dat = pathlib.Path(bin_path).read_bytes()
    out = pathlib.Path(outdir); out.mkdir(parents=True, exist_ok=True)
    cands = scan_autotables(dat)
    idx_lines = [f"# Auto-discovered tables for `{pathlib.Path(bin_path).name}`",""]
    for k,(score, byte_off, rows, cols, dtype, endian) in enumerate(cands, 1):
        # re-read as specified dtype/endian
        base = np.uint16 if dtype=="u16" else np.int16
        dt_np = np.dtype(base).newbyteorder('<' if endian=='little' else '>')
        need = rows*cols*dt_np.itemsize
        buf = dat[byte_off:byte_off+need]
        if len(buf) < need:
            continue
        Z = np.frombuffer(buf, dtype=dt_np).astype(np.float64).reshape((rows, cols))

        # plausible axes
        X = np.linspace(1000, 1000+250*(cols-1), cols)
        Y = np.linspace(20,   20+5*(rows-1),   rows)
        XX, YY = np.meshgrid(X, Y)

        name = f"AUTO_{k:02d}_off0x{byte_off:X}_{rows}x{cols}_{dtype}_{endian}"
        safe = name
        pair_png = os.path.join(out, f"{safe}.pair.png")
        surface_pair(pair_png, name, XX, YY, Z, None)
        heat_png = os.path.join(out, f"{safe}.heatmap.png")
        heatmap_table_png(heat_png, XX, YY, Z)
        idx_lines.append(f"- `{name}` @ **0x{byte_off:X}**, shape {rows}×{cols}, {dtype}/{endian}  ")
        idx_lines.append(f"  ![{name}]({os.path.relpath(pair_png, out)})")
        idx_lines.append(f"  ![{name} table]({os.path.relpath(heat_png, out)})")
        idx_lines.append("")
    with open(os.path.join(out, "INDEX.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(idx_lines) + "\n")


# ---------------- MAIN ----------------

def main():
    ap = argparse.ArgumentParser(description="ECU map visualizer")
    ap.add_argument("--bins", default="rawdata/**/*.bin")
    ap.add_argument("--specs", default="mapspecs/**/*.y?(a)ml")
    ap.add_argument("--deepseek", default="deepseek/maps/**/*.json")
    ap.add_argument("--outdir", default="out/mapviz")
    ap.add_argument("--autodiscover", action="store_true",
                    help="scan BIN for likely 2D tables when no specs are provided")
    args = ap.parse_args()

    bin_paths = glob.glob(args.bins, recursive=True)
    spec_objs = load_specs([args.specs])
    ds_index = index_deepseek([args.deepseek])

    # flatten maps from all specs
    all_maps=[]
    for spec in spec_objs:
        for m in (spec.get("maps") or []):
            all_maps.append(m)

    pathlib.Path(args.outdir).mkdir(parents=True, exist_ok=True)

    index_lines = ["# Map Visualization Index", ""]
    if not bin_paths:
        print(f"[INFO] no .bin matched: {args.bins}", file=sys.stderr)

    for binp in bin_paths:
        base = pathlib.Path(binp).name
        dst = pathlib.Path(args.outdir) / pathlib.Path(base).with_suffix("")
        dst.mkdir(parents=True, exist_ok=True)

        if (not all_maps) and (args.autodiscover or True):
            # If no specs, we auto-scan by default to be helpful
            auto_dir = dst / "_auto"
            autodiscover_for_bin(binp, str(auto_dir))

        rep = render_report(binp, str(dst), all_maps, ds_index)
        index_lines.append(f"- [{base}]({os.path.relpath(rep, args.outdir)})")

    with open(os.path.join(args.outdir, "INDEX.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(index_lines) + "\n")


if __name__ == "__main__":
    main()
