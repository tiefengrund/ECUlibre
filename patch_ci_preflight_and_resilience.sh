#!/usr/bin/env bash
set -euo pipefail

mkdir -p scripts tools .github/workflows reports

echo "==> Write scripts/preflight_bins.sh"
cat > scripts/preflight_bins.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
echo "== LFS status =="
git lfs ls-files -l || echo "(no LFS files tracked)"
echo
echo "== Changed BINs (or all on first push) =="
BEFORE="${BEFORE:-${GITHUB_EVENT_BEFORE:-${GITHUB_BEFORE:-}}}"
SHA="${SHA:-${GITHUB_SHA:-}}"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [[ -z "$BEFORE" || "$BEFORE" == 0000000000000000000000000000000000000000 ]]; then
    mapfile -t BINS < <(git ls-files 'rawdata/**/*.bin' 'rawdata/*.bin' 2>/dev/null | sort)
  else
    mapfile -t BINS < <(git diff --name-only "$BEFORE" "$SHA" -- 'rawdata/**/*.bin' 'rawdata/*.bin' | sort)
  fi
else
  mapfile -t BINS < <(find rawdata -type f -name '*.bin' -print | sort)
fi

if [[ "${#BINS[@]}" -eq 0 ]]; then
  echo "(none)"; exit 0
fi

for f in "${BINS[@]}"; do
  [ -f "$f" ] || { echo "MISSING: $f (not a file)"; continue; }
  bytes=$(wc -c < "$f" | tr -d ' ')
  echo "-- $f  (${bytes} bytes)"
  # Erkenne LFS-Pointer (beginnt mit 'version https://git-lfs.github.com/spec/v1')
  if head -c 60 "$f" | grep -q "git-lfs.github.com/spec"; then
    echo "   !! LFS POINTER DETECTED (file content not downloaded) !!"
  else
    printf "   head: "; head -c 16 "$f" | xxd -p; echo
  fi
done
BASH
chmod +x scripts/preflight_bins.sh

echo "==> Harden tools/analyze_bins.sh (per-file resilience + error logs)"
# Falls Datei existiert -> patchen; sonst minimal anlegen.
if [ -f tools/analyze_bins.sh ]; then
  awk '
    BEGIN{patched=0}
    /for f in "\$\{BINS\[@\]\}"/,0 {
      if ($0 ~ /python scripts\.analyze_med17\.py/ && patched==0) {
        print "  {"
        print "    set +e"
        print "    echo \">> HEX: $f -> $rep/dump.hex\""
        print "    python scripts/dump_hex.py \"$f\" > \"$rep/dump.hex\" 2>\"$rep/error.txt\" || true"
        print "    if [ -f scripts/analyze_med17.py ]; then"
        print "      echo \">> ANALYZE: $f -> $out\""
        print "      python scripts/analyze_med17.py \"$f\" --out \"$out\" >>\"$rep/error.txt\" 2>&1 || true"
        print "    fi"
        print "    if [ -f scripts/analyze_and_report.py ]; then"
        print "      echo \">> REPORT: $f -> reports/\""
        print "      python scripts/analyze_and_report.py --bin \"$f\" --analysis-dir \"$out\" --reports-root reports --mode \"${MODE:-power}\" >>\"$rep/error.txt\" 2>&1 || true"
        print "    fi"
        print "    if [ -f \"$out/analysis_summary.yaml\" ]; then"
        print "      cp -f \"$out/analysis_summary.yaml\" \"$rep/analysis_summary.yaml\" || true"
        print "      if python -c \"import yaml\" >/dev/null 2>&1; then"
        print "        python scripts/emit_json.py \"$out/analysis_summary.yaml\" > \"$rep/analysis_summary.json\" 2>>\"$rep/error.txt\" || true"
        print "      fi"
        print "    fi"
        print "    set -e"
        print "  }"
        print "  continue"
        patched=1; next
      }
    }
    {print}
  ' tools/analyze_bins.sh > tools/analyze_bins.sh.tmp && mv tools/analyze_bins.sh.tmp tools/analyze_bins.sh
  chmod +x tools/analyze_bins.sh
else
  cat > tools/analyze_bins.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p reports med17_analysis
mapfile -t BINS < <(find rawdata -type f -name '*.bin' -print | sort)
for f in "${BINS[@]}"; do
  base="$(basename "$f")"; stem="${base%.*}"; out="med17_analysis/$stem"; rep="reports/$stem"
  mkdir -p "$out" "$rep"
  { set +e
    echo ">> HEX: $f -> $rep/dump.hex"
    python scripts/dump_hex.py "$f" > "$rep/dump.hex" 2>"$rep/error.txt" || true
    if [ -f scripts/analyze_med17.py ]; then
      echo ">> ANALYZE: $f -> $out"
      python scripts/analyze_med17.py "$f" --out "$out" >>"$rep/error.txt" 2>&1 || true
    fi
    if [ -f scripts/analyze_and_report.py ]; then
      echo ">> REPORT: $f -> reports/"
      python scripts/analyze_and_report.py --bin "$f" --analysis-dir "$out" --reports-root reports --mode "${MODE:-power}" >>"$rep/error.txt" 2>&1 || true
    fi
    if [ -f "$out/analysis_summary.yaml" ]; then
      cp -f "$out/analysis_summary.yaml" "$rep/analysis_summary.yaml" || true
      if python -c "import yaml" >/dev/null 2>&1; then
        python scripts/emit_json.py "$out/analysis_summary.yaml" > "$rep/analysis_summary.json" 2>>"$rep/error.txt" || true
      fi
    fi
    set -e
  }
done
BASH
  chmod +x tools/analyze_bins.sh
fi

echo "==> Inject Preflight step into workflow (.github/workflows/analyze.yml)"
if [ -f .github/workflows/analyze.yml ]; then
  awk '
    BEGIN{ins=0}
    /- name: Setup Python/ && ins==0 { print; print ""; print "      - name: Preflight LFS & BIN list"; print "        env:"; print "          BEFORE: ${{ github.event.before }}"; print "          SHA: ${{ github.sha }}"; print "        run: |"; print "          bash scripts/preflight_bins.sh"; ins=1; next }
    { print }
  ' .github/workflows/analyze.yml > .github/workflows/analyze.yml.tmp && mv .github/workflows/analyze.yml.tmp .github/workflows/analyze.yml
else
  echo "WARN: workflow file not found; skipping injection."
fi

git add scripts/preflight_bins.sh tools/analyze_bins.sh .github/workflows/analyze.yml 2>/dev/null || true
echo "✅ Done. Commit & push:"
echo "   git commit -m '[skip ci] ci: add LFS preflight + per-file resilience & error logs'"
echo "   git push"
