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
