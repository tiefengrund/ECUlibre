#!/usr/bin/env bash
set -euo pipefail

echo "==> Overwrite scripts/preference_guard.sh (default to power, no hard fail)"
mkdir -p scripts prefs
cat > scripts/preference_guard.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

COMMIT_MSG="${COMMIT_MSG:-}"
PREF_MODE_FILE="prefs/mode"
DISPATCH_MODE="${DISPATCH_MODE:-}"      # workflow_dispatch input
DEFAULT_IF_EMPTY="${DEFAULT_IF_EMPTY:-power}"  # default mode if none provided

pick_mode(){ case "$1" in power|smooth) return 0;; *) return 1;; esac; }

MODE=""

# 1) parse from commit message tag like [power] or [DD-AB123 power]
if [[ -n "$COMMIT_MSG" ]]; then
  TAG="$(grep -o '\[[^]]*\]' <<<"$COMMIT_MSG" | tail -n1 | sed 's/^\[//; s/\]$//')"
  if [[ -n "$TAG" ]]; then
    read -r -a TOKS <<<"$TAG"
    CAND="${TOKS[-1],,}"
    if pick_mode "$CAND"; then MODE="$CAND"; fi
  fi
fi

# 2) from prefs/mode
if [[ -z "$MODE" && -f "$PREF_MODE_FILE" ]]; then
  FILE_MODE="$(tr -d '\r\n' < "$PREF_MODE_FILE" | tr '[:upper:]' '[:lower:]')"
  if pick_mode "$FILE_MODE"; then MODE="$FILE_MODE"; fi
fi

# 3) from workflow_dispatch
if [[ -z "$MODE" && -n "$DISPATCH_MODE" ]]; then
  LOW="$(echo "$DISPATCH_MODE" | tr '[:upper:]' '[:lower:]')"
  if pick_mode "$LOW"; then MODE="$LOW"; fi
fi

# 4) default fallback
if [[ -z "$MODE" ]]; then MODE="$DEFAULT_IF_EMPTY"; fi

mkdir -p prefs
echo "$MODE" > "$PREF_MODE_FILE"

# expose for GH Actions
{ echo "MODE=$MODE" >> "${GITHUB_OUTPUT:-/dev/null}"; } 2>/dev/null || true
echo "Selected MODE=$MODE"
BASH
chmod +x scripts/preference_guard.sh

guard_commit_step () {
  local wf="$1"
  [[ -f "$wf" ]] || { echo "skip: $wf not found"; return; }
  echo "==> Patch commit step guard in $wf"
  awk '
    BEGIN{buf=""; in_commit=0}
    {
      if ($0 ~ /- name: Commit reports back to repo/) {
        print $0
        getline
        print "        if: always()"
        print "        run: |"
        print "          set -euo pipefail"
        print "          git config user.name \"github-actions\""
        print "          git config user.email \"github-actions@users.noreply.github.com\""
        print "          # stage only if dirs exist"
        print "          if [ -d reports ]; then git add -A reports/; fi"
        print "          if [ -d prefs ];   then git add -A prefs/;   fi"
        print "          if git diff --cached --quiet; then"
        print "            echo \"No report changes to commit.\""
        print "            exit 0"
        print "          fi"
        print "          git commit -m \"[skip ci] Add analysis reports\""
        print "          git push"
        in_commit=1
        next
      }
      if (in_commit) {
        # skip old body until next step (line not starting with 6 spaces)
        if ($0 !~ /^      /) { in_commit=0; print $0 }
        next
      }
      print $0
    }
  ' "$wf" > "$wf.tmp" && mv "$wf.tmp" "$wf"
}

add_changed_fallback () {
  local wf="$1"
  [[ -f "$wf" ]] || { echo "skip: $wf not found"; return; }
  echo "==> Patch CHANGED fallback in $wf"
  # replace single-line CHANGED=... with robust block
  sed -i.bak \
    -e "s#CHANGED=\$(git diff --name-only \"\\$BEFORE\" \"\\$SHA\" -- 'rawdata/**/*.bin' 'rawdata/*.bin' || true)#if [ -z \"\\$BEFORE\" ] || [ \"\\$BEFORE\" = \"0000000000000000000000000000000000000000\" ]; then\n          CHANGED=\$(git ls-files 'rawdata/**/*.bin' 'rawdata/*.bin' 2>/dev/null || true)\n        else\n          CHANGED=\$(git diff --name-only \"\\$BEFORE\" \"\\$SHA\" -- 'rawdata/**/*.bin' 'rawdata/*.bin' || true)\n        fi#g" \
    "$wf" 2>/dev/null || true
  rm -f "$wf.bak"
}

# Apply to push workflow
[[ -f .github/workflows/analyze.yml ]] && add_changed_fallback .github/workflows/analyze.yml
guard_commit_step .github/workflows/analyze.yml

# Apply to PR workflow if present
[[ -f .github/workflows/pr_analyze.yml ]] && guard_commit_step .github/workflows/pr_analyze.yml

git add scripts/preference_guard.sh .github/workflows/analyze.yml .github/workflows/pr_analyze.yml 2>/dev/null || true
echo "✅ Hotfix staged. Commit & push:"
echo "   git commit -m '[skip ci] fix: default pref=power + guarded commit step + CHANGED fallback'"
echo "   git push"
