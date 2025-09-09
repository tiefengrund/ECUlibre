#!/usr/bin/env bash
set -euo pipefail

patch_step () {
  local wf="$1"
  [ -f "$wf" ] || { echo "skip: $wf not found"; return; }
  awk '
    BEGIN{in_step=0}
    /- name: Commit reports back to repo/ {print; in_step=1; getline; while ($0 ~ /^  /) {getline}; 
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
      # after injecting step body, continue printing the rest of the file
      print $0; in_step=0; next
    }
    {print}
  ' "$wf" > "$wf.tmp" && mv "$wf.tmp" "$wf"
  echo "patched: $wf"
}

patch_step ".github/workflows/analyze.yml"
patch_step ".github/workflows/pr_analyze.yml"

git add .github/workflows/analyze.yml .github/workflows/pr_analyze.yml 2>/dev/null || true
echo "✅ Patch applied. Now commit & push:"
echo "   git commit -m '[skip ci] fix: guard commit step when reports/ missing'"
echo "   git push"
