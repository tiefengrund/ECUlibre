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
