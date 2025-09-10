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
