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
