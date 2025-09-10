#!/usr/bin/env bash
set -euo pipefail

mkdir -p scripts tools .github/workflows reports rawdata

echo "==> Create scripts/dump_hex.py"
cat > scripts/dump_hex.py <<'PY'
#!/usr/bin/env python3
# Hexdump ähnlich 'xxd': Offset, 16 Bytes/Zeile, ASCII-Spalte
import sys
from pathlib import Path

def hexdump(path: Path, out):
    data = path.read_bytes()
    n = len(data)
    for off in range(0, n, 16):
        chunk = data[off:off+16]
        hex_pairs = " ".join(f"{b:02x}" for b in chunk)
        # pad to 16 bytes columns (3 chars incl space each)
        pad = "   " * (16 - len(chunk))
        def printable(b): 
            return 32 <= b < 127
        ascii_ = "".join(chr(b) if printable(b) else "." for b in chunk)
        out.write(f"{off:08x}  {hex_pairs}{pad}  |{ascii_}|\n")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: dump_hex.py <input.bin> [> dump.hex]", file=sys.stderr)
        sys.exit(1)
    hexdump(Path(sys.argv[1]), sys.stdout)
PY
chmod +x scripts/dump_hex.py

echo "==> Create scripts/emit_json.py (YAML -> JSON)"
cat > scripts/emit_json.py <<'PY'
#!/usr/bin/env python3
import sys, json
from pathlib import Path
try:
    import yaml
except ImportError as e:
    print("pyyaml not installed. pip install pyyaml", file=sys.stderr)
    sys.exit(2)

def main():
    if len(sys.argv) < 2:
        print("usage: emit_json.py <analysis_summary.yaml> [> analysis_summary.json]", file=sys.stderr)
        sys.exit(1)
    ypath = Path(sys.argv[1])
    data = yaml.safe_load(ypath.read_text(encoding="utf-8"))
    json.dump(data, sys.stdout, indent=2, ensure_ascii=False)

if __name__ == "__main__":
    main()
PY
chmod +x scripts/emit_json.py

# Ensure there is a simple orchestrator (create or extend)
if [ ! -f tools/analyze_bins.sh ]; then
  echo "==> Create tools/analyze_bins.sh (simple orchestrator)"
  cat > tools/analyze_bins.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
MODE="${MODE:-power}"
COMMIT_MSG="${COMMIT_MSG:-}"
if echo "$COMMIT_MSG" | grep -qi '\[smooth\]'; then MODE="smooth"; fi
echo ">> Mode: $MODE"
mkdir -p med17_analysis reports
mapfile -t BINS < <(find rawdata -type f -name '*.bin' -print | sort)
if [ "${#BINS[@]}" -eq 0 ]; then
  echo ">> No .bin in rawdata/"
  exit 0
fi
for f in "${BINS[@]}"; do
  base="$(basename "$f")"; stem="${base%.*}"
  out="med17_analysis/$stem"; mkdir -p "$out"
  rep="reports/$stem"; mkdir -p "$rep"
  echo ">> Analyze $f -> $out"
  python scripts/analyze_med17.py "$f" --out "$out"
  python scripts/analyze_and_report.py --bin "$f" --analysis-dir "$out" --reports-root reports --mode "$MODE"
  # Exports: HEX + JSON (from YAML)
  echo ">> Export hex/json for $f"
  python scripts/dump_hex.py "$f" > "$rep/dump.hex"
  if [ -f "$out/analysis_summary.yaml" ]; then
    python scripts/emit_json.py "$out/analysis_summary.yaml" > "$rep/analysis_summary.json"
    # Kopiere YAML zusätzlich neben JSON in reports/
    cp -f "$out/analysis_summary.yaml" "$rep/analysis_summary.yaml"
  fi
done
BASH
  chmod +x tools/analyze_bins.sh
else
  echo "==> Patch tools/analyze_bins.sh to add hex/json export"
  # idempotent append: add block if not present
  if ! grep -q "dump_hex.py" tools/analyze_bins.sh; then
    awk '
      1;
      /analyze_and_report\.py/ && added==0 {
        print "  # Exports: HEX + JSON (from YAML)"; 
        print "  echo \">> Export hex/json for $f\"";
        print "  python scripts/dump_hex.py \"$f\" > \"$rep/dump.hex\"";
        print "  if [ -f \"$out/analysis_summary.yaml\" ]; then";
        print "    python scripts/emit_json.py \"$out/analysis_summary.yaml\" > \"$rep/analysis_summary.json\"";
        print "    cp -f \"$out/analysis_summary.yaml\" \"$rep/analysis_summary.yaml\"";
        print "  fi";
        added=1
      }
    ' tools/analyze_bins.sh > tools/analyze_bins.sh.tmp && mv tools/analyze_bins.sh.tmp tools/analyze_bins.sh
    chmod +x tools/analyze_bins.sh
  fi
fi

# Minimal workflow: if not present, create; else patch to include pyyaml + handover artifact
WF=.github/workflows/analyze.yml
if [ ! -f "$WF" ]; then
  echo "==> Create simple workflow"
  cat > "$WF" <<'YAML'
name: ECU Analysis (Simple)

on:
  push:
    paths:
      - 'rawdata/**/*.bin'
      - 'rawdata/*.bin'

jobs:
  analyze:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: 'pip'

      - name: Install deps
        run: |
          python -m pip install --upgrade pip
          if [ -f requirements.txt ]; then
            pip install -r requirements.txt
          else
            pip install numpy pandas matplotlib pyyaml
          fi

      - name: Run analysis (default power; [smooth] via commit tag)
        env:
          COMMIT_MSG: ${{ github.event.head_commit.message }}
        run: |
          bash tools/analyze_bins.sh

      - name: Upload artifacts (reports + med17_analysis)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: ecu-analysis-${{ github.run_id }}
          path: |
            reports/
            med17_analysis/
          retention-days: 14

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
YAML
else
  echo "==> Patch workflow to ensure PyYAML and handover artifact"
  # Ensure pyyaml is installed
  if ! grep -q "pyyaml" "$WF"; then
    sed -i 's/pip install numpy pandas matplotlib/& pyyaml/' "$WF" || true
  fi
  # Add handover artifact step if missing
  if ! grep -q "Upload handover" "$WF"; then
    cat >> "$WF" <<'YAML'

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
YAML
  fi
fi

echo "==> Stage changes"
git add scripts tools .github/workflows/analyze.yml

echo "✅ Done. Commit & push:"
echo "   git commit -m '[skip ci] analysis exports: add hex + yaml->json + handover artifact'"
echo "   git push"
