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

def apply_dark_theme():
    import matplotlib as mpl
    import matplotlib.pyplot as plt
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
    })

ap.add_argument("--autodiscover", action="store_true",
                help="scan BIN for likely 2D tables (no specs needed)")

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

def scan_autotables(bin_bytes: bytes,
                    shapes=((16,16),(12,16),(16,20),(10,16),(8,16)),
                    dtypes=("u16","s16"),
                    endians=("little","big"),
                    stride_align=2,
                    topk=6):
    import numpy as np
    H=[]
    n = len(bin_bytes)
    for dtype in dtypes:
        itemsize = np.dtype(np.uint16 if dtype=="u16" else np.int16).itemsize
        for endian in endians:
            code = ("<" if endian=="little" else ">") + ("u2" if dtype=="u16" else "i2")
            arr = np.frombuffer(bin_bytes, dtype=np.dtype(code))
            for rows, cols in shapes:
                block_items = rows*cols
                step = max(1, stride_align//itemsize)
                for i in range(0, len(arr)-block_items, step):
                    Z = arr[i:i+block_items].astype(np.float64).reshape((rows,cols))
                    # Score: glatt + sinnvoller Bereich
                    rng = Z.max()-Z.min()
                    if not (5 <= rng <= 10000):  # grober Filter
                        continue
                    # Laplacian energy (je kleiner, desto glatter)
                    gy, gx = np.gradient(Z)
                    lap = (gx**2 + gy**2).mean()
                    # Monotonie grob
                    mono = np.mean(np.diff(Z, axis=1) >= 0) + np.mean(np.diff(Z, axis=0) >= 0)
                    score = lap - 0.1*mono  # niedriger ist besser
                    H.append((score, i*itemsize, rows, cols, dtype, endian))
    H.sort(key=lambda x: x[0])
    return H[:topk]

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
    import matplotlib.pyplot as plt
    from mpl_toolkits.mplot3d import Axes3D  # noqa: F401
    apply_dark_theme()

    # Colormaps passen gut: "turbo" (hell), "viridis" (dezenter)
    cmap1 = "turbo"
    cmap2 = "plasma"
    png_heat = os.path.join(out_dir, f"{safe}.heatmap.png")
    heatmap_table_png(png_heat, X, Y, Zbin)
    md.append(f"![{name} table]({os.path.relpath(png_heat)})")
    md.append("")

    def _surface(ax, X, Y, Z, label, cmap):
        surf = ax.plot_surface(X, Y, Z, cmap=cmap, linewidth=0, antialiased=True, alpha=0.95, shade=True)
        # dezentes Wireframe
        ax.plot_wireframe(X, Y, Z, rstride=max(1,int(X.shape[0]/8)), cstride=max(1,int(X.shape[1]/8)),
                          color=(1,1,1,0.15), linewidth=0.6)
        # rote Stützpunkte
        ax.scatter(X, Y, Z, c="#ff3b3b", s=8, depthshade=False)
        # Konturlinien auf die "Bodenplatte" projizieren
        ax.contour(X, Y, Z, zdir='z', offset=Z.min(), cmap="Greys", linewidths=0.6, alpha=0.8)
        ax.set_title(label, pad=12)
        ax.set_xlabel("Engine Speed [rpm]")
        ax.set_ylabel("Inlet Manifold Pressure [kPa]")
        ax.set_zlabel("[%]")

        # dunkle 3D-Panes
        for pane in [ax.w_xaxis, ax.w_yaxis, ax.w_zaxis]:
            pane.set_pane_color((0,0,0,0.0))
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
        for s in info["strings"]:
            s = s.replace("|","\\|")
            md.append(f"- `{s}`")
        md.append("")

#        if info["strings"]:
#            md.append("### Strings (first 40)")
#            md += [f"- `{s.replace('|','\\|')}`" for s in info["strings"]]
#            md.append("")

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
                def heatmap_table_png(png_path, X, Y, Z):
                    """Farbtabelle mit Zahlenbeschriftung im Stil des Beispiels."""
                    import matplotlib.pyplot as plt
                    apply_dark_theme()
                
                    fig = plt.figure(figsize=(14,5), facecolor="#000")
                    ax = fig.add_subplot(111)
                    im = ax.imshow(Z, aspect="auto", cmap="turbo", origin="upper")
                    # Achsen-Ticks mit echten X/Y-Werten
                    # (bei vielen Zellen nur eine Auswahl, sonst wird's unleserlich)
                    max_ticks = 16
                    x_idx = np.linspace(0, Z.shape[1]-1, min(Z.shape[1], max_ticks), dtype=int)
                    y_idx = np.linspace(0, Z.shape[0]-1, min(Z.shape[0], max_ticks), dtype=int)
                    ax.set_xticks(x_idx, [f"{X[0,i]:.0f}" for i in x_idx], rotation=0)
                    ax.set_yticks(y_idx, [f"{Y[i,0]:.0f}" for i in y_idx])
                
                    # Zahlenlabel in jeder Zelle (bei großen Matrizen ggf. ausdünnen)
                    step_r = 1 if Z.shape[0] <= 20 else int(np.ceil(Z.shape[0]/20))
                    step_c = 1 if Z.shape[1] <= 20 else int(np.ceil(Z.shape[1]/20))
                    for r in range(0, Z.shape[0], step_r):
                        for c in range(0, Z.shape[1], step_c):
                            ax.text(c, r, f"{Z[r,c]:.1f}", ha="center", va="center", fontsize=7, color="#000" if Z[r,c] < Z.mean() else "#fff")
                
                    ax.set_xlabel("Engine Speed [rpm]")
                    ax.set_ylabel("Inlet Manifold Pressure [kPa]")
                    ax.grid(False)
                    fig.colorbar(im, ax=ax, fraction=0.02, pad=0.02)
                    fig.tight_layout()
                    fig.savefig(png_path, dpi=220, bbox_inches="tight")
                    plt.close(fig)
        rep = os.path.join(dst, "REPORT.md")
        with open(rep, "w", encoding="utf-8") as f: f.write("\n".join(md) + "\n")
        index_lines.append(f"- [{base}]({os.path.relpath(rep, a.outdir)})")

    with open(os.path.join(a.outdir, "INDEX.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(index_lines) + "\n")

if __name__ == "__main__":
    main()
