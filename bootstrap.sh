#!/usr/bin/env bash
set -euo pipefail

OWNER="tiefengrund"
REPO="ECUlibre"
IMAGE="ghcr.io/${OWNER}/${REPO}/med17-analyzer:latest"

echo "==> Create dirs"
mkdir -p .github/workflows scripts bins

echo "==> Write .github/workflows/analyze.yml"
cat > .github/workflows/analyze.yml <<EOF
name: ECU Analysis

on:
  push:
    paths:
      - 'bins/**/*.bin'
      - 'bins/*.bin'

jobs:
  analyze:
    runs-on: ubuntu-latest
    container: ${IMAGE}
    permissions:
      contents: read
      packages: read
    steps:
      - uses: actions/checkout@v4

      - name: Run analyzer on changed BINs
        shell: bash
        run: |
          set -euo pipefail
          mkdir -p med17_analysis
          BEFORE=\${{ github.event.before }}
          SHA=\${{ github.sha }}
          CHANGED=\$(git diff --name-only "\$BEFORE" "\$SHA" -- 'bins/**/*.bin' 'bins/*.bin' || true)
          if [ -z "\$CHANGED" ]; then
            echo "Keine neuen/änderten BINs."
            exit 0
          fi
          for f in \$CHANGED; do
            base=\$(basename "\$f")
            out="med17_analysis/\${base%.*}"
            mkdir -p "\$out"
            echo "Analysiere \$f -> \$out"
            python /app/analyze_med17.py "\$f" --out "\$out"
          done

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: med17_analysis
          path: med17_analysis/
          retention-days: 14
EOF

echo "==> Write Dockerfile"
cat > Dockerfile <<'EOF'
FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
WORKDIR /app
COPY scripts/analyze_med17.py /app/analyze_med17.py
ENTRYPOINT ["python", "/app/analyze_med17.py"]
EOF

echo "==> Write requirements.txt"
cat > requirements.txt <<'EOF'
numpy==2.0.0
pandas==2.2.2
matplotlib==3.9.0
EOF

echo "==> Write scripts/analyze_med17.py"
cat > scripts/analyze_med17.py <<'EOF'
# -*- coding: utf-8 -*-
"""
MED17 VR BIN Analyzer
- Grundanalyse: Größe, Hashes, 64KiB Block-Checksummen
- Entropie (4KiB Fenster) + Plot
- Map-Heuristik: Achsenkandidaten (int16/uint16/float32 LE), 2D/3D Maps
- Export: CSVs + YAML-Summary

Usage:
  python analyze_med17.py <input.bin> --out <out_dir>
"""
import argparse, hashlib, json
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

def shannon_entropy(b: bytes) -> float:
    if not b: return 0.0
    arr = np.frombuffer(b, dtype=np.uint8)
    counts = np.bincount(arr, minlength=256)
    probs = counts / float(len(arr))
    nz = probs[probs > 0]
    return float(-(nz * np.log2(nz)).sum())

def block_additive32(b: bytes) -> int:
    return int(sum(b) & 0xFFFFFFFF)

def view_as(dtype, b: bytes):
    itemsize = np.dtype(dtype).itemsize
    trim = len(b) - (len(b) % itemsize)
    return np.frombuffer(memoryview(b)[:trim], dtype=dtype)

def find_monotonic_runs(arr: np.ndarray, min_len=8, max_len=128):
    if arr.size < min_len: return []
    diffs = np.diff(arr)
    inc = np.isfinite(diffs) & (diffs > 0)
    runs, start = [], 0
    for i in range(len(inc)):
        if not inc[i]:
            run_len = (i + 1) - start
            if min_len <= run_len <= max_len:
                runs.append((start, run_len))
            start = i + 1
    run_len = len(arr) - start
    if min_len <= run_len <= max_len:
        runs.append((start, run_len))
    return runs

def extract_block_stats(data: bytes, start_offset: int, num_items: int, dtype: str):
    itemsize = 2 if dtype in ("int16_le", "uint16_le") else 4
    end = start_offset + num_items * itemsize
    if end > len(data) or start_offset < 0: return None
    if dtype == "int16_le":
        arr = np.frombuffer(memoryview(data)[start_offset:end], dtype="<i2")
    elif dtype == "uint16_le":
        arr = np.frombuffer(memoryview(data)[start_offset:end], dtype="<u2")
    elif dtype == "float32_le":
        arr = np.frombuffer(memoryview(data)[start_offset:end], dtype="<f4")
    else:
        return None
    if arr.size == 0 or not np.all(np.isfinite(arr)): return None
    std = float(np.std(arr)); mean = float(np.mean(arr))
    if not np.isfinite(std): return None
    return {"std": std, "mean": mean}

def main():
    p = argparse.ArgumentParser()
    p.add_argument("input", help="MED17 VR BIN")
    p.add_argument("--out", required=True, help="Output directory")
    p.add_argument("--entropy-window", type=int, default=4096)
    p.add_argument("--block-size", type=int, default=64*1024)
    p.add_argument("--axis-min", type=int, default=8)
    p.add_argument("--axis-max", type=int, default=128)
    p.add_argument("--gap-candidates", type=str, default="0,16,32,64,128,256")
    args = p.parse_args()

    in_path = Path(args.input)
    out_dir = Path(args.out); out_dir.mkdir(parents=True, exist_ok=True)
    data = in_path.read_bytes(); size = len(data)

    md5 = hashlib.md5(data).hexdigest()
    sha1 = hashlib.sha1(data).hexdigest()
    sha256 = hashlib.sha256(data).hexdigest()

    # Block checksums
    block_rows = []
    for i in range(0, size, args.block_size):
        block = data[i:i + args.block_size]
        s = block_additive32(block)
        block_rows.append({"block_start": i, "block_end": min(i + args.block_size, size), "additive32": f"0x{s:08X}"})
    blocks_df = pd.DataFrame(block_rows)
    blocks_csv = out_dir / "block_checksums.csv"; blocks_df.to_csv(blocks_csv, index=False)

    # Entropy windows
    ent_rows = []
    w = args.entropy_window
    for i in range(0, size, w):
        chunk = data[i:i + w]
        H = shannon_entropy(chunk)
        ent_rows.append({"offset": i, "length": len(chunk), "entropy_bits_per_byte": H})
    ent_df = pd.DataFrame(ent_rows)
    ent_csv = out_dir / "entropy_windows.csv"; ent_df.to_csv(ent_csv, index=False)

    # Entropy plot
    plt.figure()
    plt.plot([r["offset"]/1024 for r in ent_rows], [r["entropy_bits_per_byte"] for r in ent_rows])
    plt.xlabel("Offset (KiB)"); plt.ylabel("Shannon entropy (bits/byte)"); plt.title("Windowed Entropy")
    plt.tight_layout()
    ent_png = out_dir / "entropy_plot.png"; plt.savefig(ent_png); plt.close()

    # Axis candidates
    axis_candidates = []
    f32 = view_as("<f4", data); i16 = view_as("<i2", data); u16 = view_as("<u2", data)
    def add_axes(arr, stride, dtype_name):
        for start, length in find_monotonic_runs(arr, args.axis_min, args.axis_max):
            off = start * stride
            vals = arr[start:start+length]
            if not np.all(np.isfinite(vals)): continue
            vmin, vmax = float(np.min(vals)), float(np.max(vals))
            if vmax - vmin < 1e-3: continue
            axis_candidates.append({"offset": int(off), "length": int(length), "dtype": dtype_name, "min": vmin, "max": vmax})
    add_axes(f32, 4, "float32_le"); add_axes(i16.astype(np.float64), 2, "int16_le"); add_axes(u16.astype(np.float64), 2, "uint16_le")

    axis_df = pd.DataFrame(axis_candidates)
    if not axis_df.empty:
        axis_df = axis_df.drop_duplicates(subset=["offset","length","dtype"]).sort_values("offset").reset_index(drop=True)

    # Map search
    maps = []; gaps = [int(x) for x in args.gap_candidates.split(',') if x.strip().isdigit()]
    axis_list = axis_df.to_dict(orient="records") if not axis_df.empty else []

    # 2D
    for ax in axis_list:
        axis_bytes = ax["length"] * (4 if ax["dtype"]=="float32_le" else 2)
        for gap in gaps:
            for dtype in ("int16_le","uint16_le","float32_le"):
                start = ax["offset"] + axis_bytes + gap
                stats = extract_block_stats(data, start, ax["length"], dtype)
                if stats and stats["std"] > 1e-3:
                    maps.append({"type":"2D","axis_dtype":ax["dtype"],"data_dtype":dtype,"axis_offset":ax["offset"],"data_offset":start,"shape":[int(ax["length"])],"std":stats["std"],"mean":stats["mean"]})
                    break
            else:
                continue
            break

    # 3D
    for i in range(len(axis_list)-1):
        ax1 = axis_list[i]
        for j in range(i+1, min(i+50, len(axis_list))):
            ax2 = axis_list[j]
            dist = ax2["offset"] - (ax1["offset"] + ax1["length"] * (4 if ax1["dtype"]=="float32_le" else 2))
            if dist < 0 or dist > 2048: continue
            for gap in gaps:
                for dtype in ("int16_le","uint16_le","float32_le"):
                    mat_start = ax2["offset"] + ax2["length"] * (4 if ax2["dtype"]=="float32_le" else 2) + gap
                    num_items = int(ax1["length"]) * int(ax2["length"])
                    stats = extract_block_stats(data, mat_start, num_items, dtype)
                    if stats and stats["std"] > 1e-3:
                        maps.append({"type":"3D","axis1_dtype":ax1["dtype"],"axis2_dtype":ax2["dtype"],"data_dtype":dtype,"axis1_offset":ax1["offset"],"axis2_offset":ax2["offset"],"data_offset":mat_start,"shape":[int(ax1["length"]),int(ax2["length"])],"std":stats["std"],"mean":stats["mean"]})
                        break
                else:
                    continue
                break

    maps_df = pd.DataFrame(maps)
    maps_csv = out_dir / "maps_summary.csv"
    if not maps_df.empty:
        maps_df["score"] = maps_df["std"]
        maps_df = maps_df.sort_values(["type","score"], ascending=[True,False]).reset_index(drop=True)
        maps_df.to_csv(maps_csv, index=False)

    # YAML summary
    def dump_yaml(d, indent=0, lines=None):
        if lines is None: lines = []
        sp = "  " * indent
        if isinstance(d, dict):
            for k, v in d.items():
                if isinstance(v, (dict, list)):
                    lines.append(f"{sp}{k}:"); dump_yaml(v, indent+1, lines)
                else:
                    if isinstance(v, str) and ":" in v and not v.startswith("/"):
                        lines.append(f'{sp}{k}: "{v}"')
                    else:
                        lines.append(f"{sp}{k}: {v}")
        elif isinstance(d, list):
            for item in d:
                if isinstance(item, (dict, list)):
                    lines.append(f"{sp}-"); dump_yaml(item, indent+1, lines)
                else:
                    lines.append(f"{sp}- {item}")
        return lines

    yaml_obj = {
        "med17_analysis": {
            "metadata": {"input_file": in_path.name, "size_bytes": size, "md5": md5, "sha1": sha1, "sha256": sha256},
            "checksums": {"block_size_bytes": args.block_size, "blocks_csv": str(blocks_csv)},
            "entropy": {
                "window_bytes": args.entropy_window,
                "csv": str(ent_csv),
                "plot_png": str(ent_png),
                "summary": {
                    "min": float(ent_df["entropy_bits_per_byte"].min()),
                    "mean": float(ent_df["entropy_bits_per_byte"].mean()),
                    "max": float(ent_df["entropy_bits_per_byte"].max()),
                },
            },
            "maps": {
                "found_count": int(len(maps)),
                "csv": str(maps_csv) if not maps_df.empty else None,
                "top_examples": (maps_df.head(20).to_dict(orient="records") if not maps_df.empty else []),
            },
        }
    }
    yaml_text = "\n".join(dump_yaml(yaml_obj))
    (out_dir / "analysis_summary.yaml").write_text(yaml_text, encoding="utf-8")

    print(json.dumps({"file": in_path.name, "size_bytes": size, "md5": md5, "sha1": sha1, "sha256": sha256,
                      "num_axes_candidates": int(len(axis_df)) if not axis_df.empty else 0,
                      "num_maps_found": int(len(maps))}, indent=2))

if __name__ == "__main__":
    main()
EOF

echo "==> Write .gitignore"
cat > .gitignore <<'EOF'
__pycache__/
*.pyc
med17_analysis/
.DS_Store
.vscode/
.idea/
EOF

echo "==> Write README.md"
cat > README.md <<EOF
# ECU Analysis (MED17) – GitHub Actions

Automatische Analyse von MED17 VR-BINs bei jedem Push. Ergebnisse als Artifacts (CSV, PNG, YAML).

## Quickstart
1. Lege deine \`*.bin\` in \`bins/\`.
2. (Optional) Analyzer-Image bauen & in GHCR pushen:

   \`\`\`bash
   export OWNER=${OWNER}
   export REPO=${REPO}
   export IMAGE=ghcr.io/\$OWNER/\$REPO/med17-analyzer:latest

   echo \$GHCR_TOKEN | docker login ghcr.io -u \$OWNER --password-stdin
   docker build -t \$IMAGE .
   docker push \$IMAGE
   \`\`\`

3. Workflow läuft automatisch bei Änderungen unter \`bins/**/*.bin\`.

**Genutztes Image:** \`${IMAGE}\`
EOF

echo "==> git add all created/updated files"
git add .github/workflows/analyze.yml Dockerfile requirements.txt scripts/analyze_med17.py .gitignore README.md

echo "Done ✅"
echo
echo "Jetzt committen und pushen:"
echo "  git commit -m 'bootstrap CI for MED17 analysis (${IMAGE})'"
echo "  git push"
