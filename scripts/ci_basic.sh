#!/usr/bin/env bash
set -euo pipefail
log(){ printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
mkdir -p out

# 1) Bootstrap (optional)
if [ -x scripts/bootstrap_eculibre.sh ]; then
  log "bootstrap"
  scripts/bootstrap_eculibre.sh
else
  log "bootstrap script not found -> skip"
fi

# 2) Shell lint (nur echte Shell-Skripte per Shebang)
if command -v shellcheck >/dev/null 2>&1 && [ -d scripts ]; then
  log "shellcheck"
  grep -rlIZ -m1 -E '^#!.*\b(bash|sh|dash|ksh)\b' scripts 2>/dev/null \
    | xargs -0 -r shellcheck
else
  log "shellcheck not available or scripts/ missing -> skip"
fi

# 3) Schema validate (optional)
if [ -f schemas/metadata.schema.yaml ] && [ -f scripts/validate_metadata.py ]; then
  log "schema validate"
  python scripts/validate_metadata.py
else
  log "schema or validator missing -> skip"
fi

# 4) Repo check (optional)
if [ -x scripts/check_repo.sh ]; then
  log "repo check"
  scripts/check_repo.sh
else
  log "check_repo.sh not found -> skip"
fi

# 5) Snapshot (nicht failing)
OS_TAG="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo generic)"
log "pack snapshot (${OS_TAG})"
zip -qr "out/structure-snapshot-${OS_TAG}.zip" rawdata patches schemas docs || true
echo "ci_basic done (${OS_TAG})" > "out/ci-basic-${OS_TAG}.log"
