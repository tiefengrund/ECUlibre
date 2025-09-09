#!/usr/bin/env bash
set -euo pipefail

# Dein Owner/Repo
OWNER="tiefengrund"
REPO="ECUlibre"
IMAGE="ghcr.io/${OWNER}/${REPO}/med17-analyzer:latest"

echo "==> Patching analyze.yml ..."
# Ersetze Platzhalter im Workflow
sed -i.bak "s#ghcr.io/OWNER/REPO/med17-analyzer:latest#${IMAGE}#g" .github/workflows/analyze.yml

echo "==> Patching README.md ..."
# Ersetze export OWNER/REPO und IMAGE Beispiel
sed -i.bak "s#export OWNER=.*#export OWNER=${OWNER}#g" README.md
sed -i.bak "s#export REPO=.*#export REPO=${REPO}#g" README.md
sed -i.bak "s#ghcr.io/\\$OWNER/\\$REPO/med17-analyzer:latest#${IMAGE}#g" README.md

echo "==> Cleaning up backup files ..."
rm -f .github/workflows/analyze.yml.bak README.md.bak

echo "==> Git add ..."
git add .github/workflows/analyze.yml README.md

echo "Fertig 🎉 — jetzt kannst du committen:"
echo "   git commit -m 'fix CI image URL to ${IMAGE}'"
