#!/usr/bin/env bash
set -euo pipefail

mkdir -p scripts tools .github/workflows recon reports

echo "==> scripts/re_scan.py"
cat > scripts/re_scan.py <<'PY'
#!/usr/bin/env python3
# Reverse-Engineering Scanner (safe, read-only)
# - ASCII & UTF-16LE strings
# - Marker-Suche (Bosch/MED/MG1/UDS/XCP/ASAM/A2L/...)
# - Entropy-Segmente (4KiB Fenster) + Labels
# - Byte-Histogramm (PNG)
# - JSON/CSV Summary
import argparse, json, math, re, zlib
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

MARKERS = [
    b"BOSCH", b"MED", b"MG1", b"ME17", b"ME7",
    b"TRICORE", b"INFINEON", b"SIEMENS",
    b"ASAM", b"A2L", b"KWP", b"UDS", b"XCP", b"CAN",
    b"SWFL", b"SWUP", b"BOOT", b"CBOOT", b"FLASH", b"CAL", b"MAP"
]

def ascii_strings(b: bytes, minlen=4):
    out=[]; cur=[]
    for x in b:
        if 32 <= x < 127:
            cur.append(x)
        else:
            if len(cur) >= minlen: out.append(bytes(cur).decode('ascii','ignore'))
            cur=[]
    if len(cur) >= minlen: out.append(bytes(cur).decode('ascii','ignore'))
    return out

def utf16le_strings(b: bytes, minlen=4):
    out=[]; cur=[]
    # read 2-byte units
    for i in range(0, len(b)-1, 2):
        ch = int.from_bytes(b[i:i+2], 'little', signed=False)
        if 32 <= ch < 127:
            cur.append(ch)
        else:
            if len(cur) >= minlen: out.append("".join(map(chr, cur)))
            cur=[]
    if len(cur) >= minlen: out.append("".join(map(chr, cur)))
    return out

def shannon_entropy(arr_u8: np.ndarray):
    if arr_u8.size == 0: return 0.0
    counts = np.bincount(arr_u8, minlength=256)
    p = counts / float(arr_u8.size)
    nz = p[p>0]
    return float(-(nz*np.log2(nz)).sum())

def segment_entropy(b: bytes, win=4096):
    rows=[]
    arr = np.frombuffer(b, dtype=np.uint8)
    for off in range(0, len(b), win):
        chunk = arr[off:off+win]
        H = shannon_entropy(chunk)
        rows.append((off, len(chunk), H))
    df = pd.DataFrame(rows, columns=["offset","length","entropy_bits_per_byte"])
    # simple run-length merge into segments (adjacent windows with label)
    def label(h):
        return "low" if h<4.5 else ("med" if h<6.5 else "high")
    df["label"] = df["entropy_bits_per_byte"].apply(label)
    segs=[]
    start=0; cur_label=df.iloc[0]["label"] if not df.empty else "low"
    for i in range(len(df)):
        lab = df.iloc[i]["label"]
        if lab != cur_label:
            off0 = int(df.iloc[start]["offset"])
            off1 = int(df.iloc[i]["offset"])
            seg = arr[off0:off1]
            segs.append({"start":off0, "end":off1, "length":off1-off0,
                         "label":cur_label, "entropy_mean":float(df.iloc[start:i]["entropy_bits_per_byte"].mean())})
            start=i; cur_label=lab
    if not df.empty:
        off0 = int(df.iloc[start]["offset"])
        off1 = int(df.iloc[len(df)-1]["offset"] + df.iloc[len(df)-1]["length"])
        seg = arr[off0:off1]
        segs.append({"start":off0, "end":off1, "length":off1-off0,
                     "label":cur_label, "entropy_mean":float(df.iloc[start:]["entropy_bits_per_byte"].mean())})
    return df, pd.DataFrame(segs)

def find_markers(b: bytes):
    hits=[]
    for m in MARKERS:
        start=0
        while True:
            idx = b.find(m, start)
            if idx==-1: break
            hits.append({"marker": m.decode('ascii','ignore'), "offset": idx})
            start = idx+1
    # crude UTF-16LE marker search (letters + zero)
    for m in MARKERS:
        pat = b"".join(x.to_bytes(2,'little') for x in m)
        start=0
        while True:
            idx = b.find(pat, start)
            if idx==-1: break
            hits.append({"marker": m.decode('ascii','ignore')+"_utf16le", "offset": idx})
            start = idx+1
    return pd.DataFrame(hits)

def byte_histogram_png(arr_u8: np.ndarray, out_png: Path):
    counts = np.bincount(arr_u8, minlength=256)
    plt.figure()
    plt.bar(range(256), counts)
    plt.xlabel("Byte value")
    plt.ylabel("Count")
    plt.title("Byte frequency histogram")
    plt.tight_layout()
    plt.savefig(out_png)
    plt.close()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    p = Path(args.bin); out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    b = p.read_bytes()
    u8 = np.frombuffer(b, dtype=np.uint8)

    # Strings
    asc = ascii_strings(b, 4)
    (out/"strings_ascii.txt").write_text("\n".join(asc), encoding="utf-8")
    u16 = utf16le_strings(b, 4)
    (out/"strings_utf16le.txt").write_text("\n".join(u16), encoding="utf-8")

    # Markers
    dfm = find_markers(b)
    if not dfm.empty:
        dfm.sort_values(["marker","offset"]).to_csv(out/"markers.csv", index=False)
    (out/"markers.json").write_text(dfm.to_json(orient="records"), encoding="utf-8")

    # Entropy windows + segments
    dfw, segs = segment_entropy(b, 4096)
    dfw.to_csv(out/"entropy_windows_4k.csv", index=False)
    segs.to_csv(out/"segments.csv", index=False)

    # Histogram
    byte_histogram_png(u8, out/"byte_histogram.png")

    # Summary JSON
    summary = {
        "input": p.name,
        "size_bytes": len(b),
        "strings": {"ascii_count": len(asc), "utf16le_count": len(u16)},
        "markers_count": 0 if dfm is None or dfm.empty else int(len(dfm)),
        "segments": {"count": 0 if segs is None or segs.empty else int(len(segs))},
        "artifacts": {
            "strings_ascii": str((out/"strings_ascii.txt").as_posix()),
            "strings_utf16le": str((out/"strings_utf16le.txt").as_posix()),
            "markers_csv": str((out/"markers.csv").as_posix()),
            "markers_json": str((out/"markers.json").as_posix()),
            "entropy_windows_csv": str((out/"entropy_windows_4k.csv").as_posix()),
            "segments_csv": str((out/"segments.csv").as_posix()),
            "byte_histogram_png": str((out/"byte_histogram.png").as_posix())
        }
    }
    (out/"re_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps({"ok": True, "summary_path": str(out/"re_summary.json")}))
if __name__ == "__main__":
    main()
PY
chmod +x scripts/re_scan.py

echo "==> tools/analyze_bins.sh erweitern (RE-Scan)"
# Falls es dein orchestrator schon gibt: RE-Block einfügen, sonst neu anlegen (light).
if [ -f tools/analyze_bins.sh ]; then
  if ! grep -q "re_scan.py" tools/analyze_bins.sh; then
    awk '
      1;
      /analyze_and_report\.py.*--mode/ && added==0 {
        print "  # Reverse-Engineering scan (strings/markers/entropy/histogram)"
        print "  rec=\"recon/$stem\"; mkdir -p \"$rec\""
        print "  python scripts/re_scan.py --bin \"$f\" --out \"$rec\" || true"
        added=1
      }
    ' tools/analyze_bins.sh > tools/analyze_bins.sh.tmp && mv tools/analyze_bins.sh.tmp tools/analyze_bins.sh
    chmod +x tools/analyze_bins.sh
  fi
else
  cat > tools/analyze_bins.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
COMMIT_MSG="${COMMIT_MSG:-}"
MODE="power"; if echo "$COMMIT_MSG" | grep -qi '\[smooth\]'; then MODE="smooth"; fi
mkdir -p med17_analysis reports recon
mapfile -t BINS < <(find rawdata -type f -name '*.bin' -print | sort)
for f in "${BINS[@]}"; do
  base="$(basename "$f")"; stem="${base%.*}"
  out="med17_analysis/$stem"; rep="reports/$stem"; rec="recon/$stem"
  mkdir -p "$out" "$rep" "$rec"
  # hex
  python scripts/dump_hex.py "$f" > "$rep/dump.hex"
  # analyze (optional)
  if [ -f scripts/analyze_med17.py ]; then python scripts/analyze_med17.py "$f" --out "$out" || true; fi
  if [ -f scripts/analyze_and_report.py ]; then python scripts/analyze_and_report.py --bin "$f" --analysis-dir "$out" --reports-root reports --mode "$MODE" || true; fi
  # yaml->json
  if [ -f "$out/analysis_summary.yaml" ]; then cp -f "$out/analysis_summary.yaml" "$rep/analysis_summary.yaml"; python scripts/emit_json.py "$out/analysis_summary.yaml" > "$rep/analysis_summary.json" || true; fi
  # RE
  python scripts/re_scan.py --bin "$f" --out "$rec" || true
done
BASH
  chmod +x tools/analyze_bins.sh
fi

echo "==> Workflow (.github/workflows/analyze.yml) um RE-Artifacts ergänzen"
# Falls kein simpler Workflow existiert, einen anlegen:
if [ ! -f .github/workflows/analyze.yml ]; then
  cat > .github/workflows/analyze.yml <<'YAML'
name: ECU Analysis (stable, LFS + RE)

on:
  push:
    paths:
      - 'rawdata/**/*.bin'
      - 'rawdata/*.bin'

jobs:
  analyze:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Checkout (with LFS)
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          lfs: true

      - name: Setup Python 3.11
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: 'pip'

      - name: Install Python deps
        run: |
          python -m pip install --upgrade pip
          if [ -f requirements.txt ]; then
            pip install -r requirements.txt
          else
            pip install numpy pandas matplotlib pyyaml
          fi

      - name: Run analysis + RE scan
        env:
          COMMIT_MSG: ${{ github.event.head_commit.message }}
          BEFORE: ${{ github.event.before }}
          SHA: ${{ github.sha }}
        run: |
          bash tools/analyze_bins.sh

      - name: Upload handover (hex+yaml+json only)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: handover-${{ github.run_id }}
          path: |
            reports/**/dump.hex
            reports/**/analysis_summary.yaml
            reports/**/analysis_summary.json
          retention-days: 30

      - name: Upload RE artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: re-${{ github.run_id }}
          path: recon/
          retention-days: 21

      - name: Upload full analysis (reports + med17_analysis)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: full-analysis-${{ github.run_id }}
          path: |
            reports/
            med17_analysis/
            recon/
          retention-days: 14
YAML
else
  # Falls Workflow schon existiert: zusätzlichen Artifact-Step für RE
  if ! grep -q "Upload RE artifacts" .github/workflows/analyze.yml; then
    cat >> .github/workflows/analyze.yml <<'YAML'

      - name: Upload RE artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: re-${{ github.run_id }}
          path: recon/
          retention-days: 21
YAML
  fi
fi

echo "==> Stage Änderungen"
git add scripts/re_scan.py tools/analyze_bins.sh .github/workflows/analyze.yml 2>/dev/null || true

echo "✅ Done. Commit & Push:"
echo "   git commit -m '[skip ci] RE pipeline: strings/markers/entropy/histogram + artifacts'"
echo "   git push"
