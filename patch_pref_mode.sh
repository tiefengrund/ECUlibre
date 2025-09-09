#!/usr/bin/env bash
set -euo pipefail

OWNER="tiefengrund"
REPO="ECUlibre"
IMAGE="ghcr.io/${OWNER}/${REPO}/med17-analyzer:latest"

echo "==> Ensuring structure"
mkdir -p .github/workflows scripts rawdata reports prefs

echo "==> Writing scripts/preference_guard.sh"
cat > scripts/preference_guard.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

COMMIT_MSG="${COMMIT_MSG:-}"
PREF_FILE="prefs/mode"
DISPATCH_MODE="${DISPATCH_MODE:-}"   # from workflow_dispatch input
GH_TOKEN="${GH_TOKEN:-}"             # in Actions: ${{ secrets.GITHUB_TOKEN }}
REPO_SLUG="${GITHUB_REPOSITORY:-}"
SHA="${GITHUB_SHA:-}"

mkdir -p prefs

pick_mode() {
  case "$1" in power|smooth) return 0;; *) return 1;; esac
}

MODE=""

# 1) from commit message tag
if [[ -n "$COMMIT_MSG" ]]; then
  if echo "$COMMIT_MSG" | grep -qi '\[power\]';  then MODE="power"; fi
  if echo "$COMMIT_MSG" | grep -qi '\[smooth\]'; then MODE="smooth"; fi
fi

# 2) from file
if [[ -z "$MODE" && -f "$PREF_FILE" ]]; then
  FILE_MODE="$(tr -d '\r\n' < "$PREF_FILE" | tr '[:upper:]' '[:lower:]')"
  if pick_mode "$FILE_MODE"; then MODE="$FILE_MODE"; fi
fi

# 3) from workflow_dispatch input
if [[ -z "$MODE" && -n "$DISPATCH_MODE" ]]; then
  LOW="$(echo "$DISPATCH_MODE" | tr '[:upper:]' '[:lower:]')"
  if pick_mode "$LOW"; then MODE="$LOW"; fi
fi

# If still not set -> open GitHub issue and fail
if [[ -z "$MODE" ]]; then
  echo "Preference not set (power/smooth). Creating issue and exiting 1."
  if [[ -n "$GH_TOKEN" && -n "$REPO_SLUG" ]]; then
    title="Präferenz nötig: sprit sparen – möglichst viel Leistung (power) oder ruhiger schalten (smooth)?"
    body=$'Bitte wähle **genau eine** Option:\n\n- `power` – möglichst viel Leistung\n- `smooth` – ruhiger schalten\n\n**So setzt du es:**\n- Datei `prefs/mode` mit Inhalt `power` **oder** `smooth` committen,\n- oder Commit-Message-Tag `[power]` bzw. `[smooth]`,\n- oder Workflow manuell starten (Input `pref_mode`).\n\nCommit: '"$SHA"
    json_payload=$(printf '{"title":%q,"body":%q}' "$title" "$body")
    curl -sS -X POST \
      -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -d "$json_payload" \
      "https://api.github.com/repos/${REPO_SLUG}/issues" >/dev/null || true
  fi
  # expose empty MODE output (for Actions step output)
  { echo "MODE=" >> "${GITHUB_OUTPUT:-/dev/null}"; } 2>/dev/null || true
  exit 1
fi

# persist + output
echo "$MODE" > "$PREF_FILE"
{ echo "MODE=$MODE" | tee -a "${GITHUB_OUTPUT:-/dev/null}"; } 2>/dev/null || true
echo "Mode selected: $MODE"
BASH
chmod +x scripts/preference_guard.sh

echo "==> Writing scripts/analyze_and_report.py (with --mode support)"
cat > scripts/analyze_and_report.py <<'PYEOF'
# -*- coding: utf-8 -*-
"""
Generate suggestions + bilingual docs after analyze_med17.py ran.

Outputs per BIN under reports/<binbase>/:
- README.de.md
- README.en.md
- analysis_summary.yaml, entropy_windows.csv, entropy_plot.png, block_checksums.csv, maps_summary.csv (copied)
"""
import argparse, shutil
from pathlib import Path
import pandas as pd

DE_TMPL = """# Analysebericht – {binname}

**ECU:** Bosch MED17.x (VR Dump)
{mode_note}

## Zusammenfassung
- Eingabe: `{binname}`
- Größe: {size_bytes} Bytes
- Hashes: MD5 {md5}, SHA1 {sha1}

## Ergebnisse
- Entropieplot: `entropy_plot.png`
- Entropie-Fenster: `entropy_windows.csv`
- Block-Checksummen: `block_checksums.csv`
- Kartenübersicht: `maps_summary.csv` ({maps_count} Kandidaten)

## Empfehlungen
{recs}

> Automatisch generiert. Bitte Ergebnisse fachlich validieren.
"""

EN_TMPL = """# Analysis Report – {binname}

**ECU:** Bosch MED17.x (VR dump)
{mode_note}

## Summary
- Input: `{binname}`
- Size: {size_bytes} bytes
- Hashes: MD5 {md5}, SHA1 {sha1}

## Results
- Entropy plot: `entropy_plot.png`
- Entropy windows: `entropy_windows.csv`
- Block checksums: `block_checksums.csv`
- Maps summary: `maps_summary.csv` ({maps_count} candidates)

## Suggestions
{recs}

> Auto-generated. Please validate technically.
"""

def suggest_from_maps(maps_csv: Path) -> list:
    if not maps_csv.exists():
        return ["Keine Karten erkannt – Heuristik enger stellen (Achsen 8–64, Gap ≤ 64 B, dtype int16/uint16 bevorzugen)."]
    try:
        df = pd.read_csv(maps_csv)
    except Exception:
        return ["Karten-CSV nicht lesbar – CSV prüfen."]
    out = []
    if not df.empty:
        c3 = df[df["type"]=="3D"] if "type" in df else df
        c2 = df[df["type"]=="2D"] if "type" in df else df
        if "score" in df.columns:
            c3 = c3.sort_values("score", ascending=False)
            c2 = c2.sort_values("score", ascending=False)
        if not c3.empty:
            out.append("3D-Kandidaten prüfen (Top Varianz): Hauptkennfelder vermutet.")
        if not c2.empty:
            out.append("2D-Kandidaten prüfen: Korrektur-/Limiter-Tabellen wahrscheinlich.")
    out += [
        "Entropietäler (niedrige Bits/Byte) als Datensegmente priorisieren, Peaks als Code/Kompression einstufen.",
        "Achsbereiche auf physikalische Plausibilität mappen (RPM 0–8000, Druck 0–4000 mbar rel., Temp -40–150 °C).",
        "Benachbarte Achsenblöcke: Achsen gefolgt von Matrix – Abstand ≤ 2 KiB testen.",
    ]
    return out

def parse_hashes_from_yaml(yaml_path: Path) -> tuple[str,str]:
    md5 = ""; sha1 = ""
    if yaml_path.exists():
        try:
            for line in yaml_path.read_text(encoding="utf-8", errors="ignore").splitlines():
                s = line.strip()
                if s.startswith("md5:"):  md5  = s.split(":",1)[1].strip()
                if s.startswith("sha1:"): sha1 = s.split(":",1)[1].strip()
        except Exception:
            pass
    return md5, sha1

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True)
    ap.add_argument("--analysis-dir", required=True, help="Output dir from analyze_med17.py")
    ap.add_argument("--reports-root", default="reports")
    ap.add_argument("--mode", choices=["power","smooth"], required=False)
    args = ap.parse_args()

    bin_path = Path(args.bin)
    analysis_dir = Path(args.analysis_dir)
    reports_root = Path(args.reports_root)
    out_dir = reports_root / bin_path.stem
    out_dir.mkdir(parents=True, exist_ok=True)

    size_bytes = bin_path.stat().st_size if bin_path.exists() else 0
    md5, sha1 = parse_hashes_from_yaml(analysis_dir / "analysis_summary.yaml")

    maps_csv = analysis_dir / "maps_summary.csv"
    maps_count = 0
    if maps_csv.exists():
        try:
            with maps_csv.open("r", encoding="utf-8", errors="ignore") as fh:
                maps_count = max(0, sum(1 for _ in fh) - 1)
        except Exception:
            maps_count = 0

    # copy artifacts
    for fname in ["analysis_summary.yaml","entropy_windows.csv","entropy_plot.png","block_checksums.csv","maps_summary.csv"]:
        src = analysis_dir / fname
        if src.exists():
            (out_dir / fname).write_bytes(src.read_bytes())

    # suggestions
    suggestions = suggest_from_maps(maps_csv)

    if args.mode == "power":
        suggestions.insert(0, "Ziel: möglichst viel Leistung – 3D-Last-/Zündkennfelder mit hoher Varianz priorisieren.")
        suggestions.append("Beachte thermische Limits & Klopfregelung – keine Hinweise zur Deaktivierung von Schutzfunktionen.")
    elif args.mode == "smooth":
        suggestions.insert(0, "Ziel: ruhiger schalten – 2D-Tabellen nahe Drehmoment-/Schaltlogik mit weichen Gradienten priorisieren.")
        suggestions.append("Schaltkomfort vor Spitzenleistung – Drehmomentanstieg flacher ausprägen.")

    recs_md = "\n".join(f"- {s}" for s in suggestions)
    mode_note = f"**Präferenz:** {args.mode}" if args.mode else "**Präferenz:** (nicht gesetzt)"

    (out_dir / "README.de.md").write_text(DE_TMPL.format(
        binname=bin_path.name, size_bytes=size_bytes, md5=md5, sha1=sha1, maps_count=maps_count, recs=recs_md, mode_note=mode_note
    ), encoding="utf-8")

    (out_dir / "README.en.md").write_text(EN_TMPL.format(
        binname=bin_path.name, size_bytes=size_bytes, md5=md5, sha1=sha1, maps_count=maps_count, recs=recs_md, mode_note=("**Preference:** "+args.mode if args.mode else "**Preference:** (unset)")
    ), encoding="utf-8")

if __name__ == "__main__":
    main()
PYEOF

echo "==> Writing .github/workflows/analyze.yml"
cat > .github/workflows/analyze.yml <<EOF
name: ECU Analysis

on:
  push:
    paths:
      - 'rawdata/**/*.bin'
      - 'rawdata/*.bin'
  workflow_dispatch:
    inputs:
      pref_mode:
        description: 'sprit sparen: power (möglichst viel Leistung) oder smooth (ruhiger schalten)'
        required: false
        type: choice
        options: [power, smooth]

jobs:
  analyze:
    runs-on: ubuntu-latest
    container: ${IMAGE}
    permissions:
      contents: write
      packages: read
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Preference check (power/smooth)
        id: pref
        env:
          GH_TOKEN: \${{ secrets.GITHUB_TOKEN }}
          COMMIT_MSG: \${{ github.event.head_commit.message }}
          DISPATCH_MODE: \${{ github.event.inputs.pref_mode }}
        run: |
          bash scripts/preference_guard.sh
        shell: bash

      - name: Run analyzer on changed BINs in rawdata/
        if: \${{ steps.pref.outputs.MODE != '' }}
        shell: bash
        run: |
          set -euo pipefail
          mkdir -p med17_analysis reports
          BEFORE=\${{ github.event.before }}
          SHA=\${{ github.sha }}
          CHANGED=\$(git diff --name-only "\$BEFORE" "\$SHA" -- 'rawdata/**/*.bin' 'rawdata/*.bin' || true)
          if [ -z "\$CHANGED" ]; then
            echo "No new/changed BINs in rawdata/."
            exit 0
          fi
          for f in \$CHANGED; do
            base=\$(basename "\$f"); stem="\${base%.*}"
            out="med17_analysis/\$stem"; mkdir -p "\$out"
            echo "Analyzing \$f -> \$out (mode=\${{ steps.pref.outputs.MODE }})"
            python /app/analyze_med17.py "\$f" --out "\$out"
            python /app/analyze_and_report.py --bin "\$f" --analysis-dir "\$out" --reports-root reports --mode "\${{ steps.pref.outputs.MODE }}"
          done

      - name: Commit reports back to repo
        if: always()
        run: |
          set -euo pipefail
          git config user.name "github-actions"
          git config user.email "github-actions@users.noreply.github.com"
          git add reports/ prefs/mode
          if git diff --cached --quiet; then
            echo "No report changes to commit."
            exit 0
          fi
          git commit -m "[skip ci] Add analysis reports (mode: \${{ steps.pref.outputs.MODE }})"
          git push

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: med17_analysis
          path: med17_analysis/
          retention-days: 14
EOF

echo "==> Staging files"
git add scripts/preference_guard.sh scripts/analyze_and_report.py .github/workflows/analyze.yml prefs || true

echo "All set ✅"
echo "Now:"
echo "  git commit -m '[skip ci] add pref-mode check + reporting pipeline'"
echo "  git push"
