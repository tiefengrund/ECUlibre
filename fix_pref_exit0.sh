#!/usr/bin/env bash
set -euo pipefail

echo "==> Overwrite scripts/preference_guard.sh (always exit 0, default=power)"
mkdir -p scripts prefs
cat > scripts/preference_guard.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
COMMIT_MSG="${COMMIT_MSG:-}"
PREF_MODE_FILE="prefs/mode"
MODE=""

# 1) aus Commit-Message: [power] oder [smooth]
if [[ -n "$COMMIT_MSG" ]]; then
  if echo "$COMMIT_MSG" | grep -qi '\[smooth\]'; then MODE="smooth"; fi
  if echo "$COMMIT_MSG" | grep -qi '\[power\]';  then MODE="power";  fi
fi

# 2) aus Datei prefs/mode
if [[ -z "$MODE" && -f "$PREF_MODE_FILE" ]]; then
  MODE="$(tr -d '\r\n' < "$PREF_MODE_FILE" | tr '[:upper:]' '[:lower:]')"
fi

# 3) Fallback: power
[[ "$MODE" == "power" || "$MODE" == "smooth" ]] || MODE="power"

mkdir -p prefs
echo "$MODE" > "$PREF_MODE_FILE"

# Outputs für GitHub Actions (best effort)
{ echo "MODE=$MODE" >> "${GITHUB_OUTPUT:-/dev/null}"; } 2>/dev/null || true
echo "Selected MODE=$MODE"
exit 0
BASH
chmod +x scripts/preference_guard.sh

# Härtung Commit-Step: stage nur, wenn Ordner existieren
harden_commit () {
  local wf="$1"; [[ -f "$wf" ]] || { echo "skip: $wf not found"; return; }
  awk '
    BEGIN{in_commit=0}
    /- name: Commit reports back to repo/ {
      print; in_commit=1; getline;
      print "        if: always()"
      print "        run: |"
      print "          set -euo pipefail"
      print "          git config user.name \"github-actions\""
      print "          git config user.email \"github-actions@users.noreply.github.com\""
      print "          if [ -d reports ]; then git add -A reports/ || true; fi"
      print "          if [ -d prefs ];   then git add -A prefs/   || true; fi"
      print "          if git diff --cached --quiet; then"
      print "            echo \"No report changes to commit.\""
      print "            exit 0"
      print "          fi"
      print "          git commit -m \"[skip ci] Add analysis reports\""
      print "          git push"
      while (getline) { if ($0 !~ /^      /) { print $0; break } }
      in_commit=0; next
    }
    { if (!in_commit) print }
  ' "$wf" > "$wf.tmp" && mv "$wf.tmp" "$wf"
}

harden_commit ".github/workflows/analyze.yml"
harden_commit ".github/workflows/pr_analyze.yml"

git add scripts/preference_guard.sh .github/workflows/analyze.yml .github/workflows/pr_analyze.yml 2>/dev/null || true
echo "✅ Staged. Commit & push:"
echo "   git commit -m '[skip ci] fix: guard always exit 0 + commit step hardened'"
echo "   git push"
