rm -f .github/workflows/hex.yml

cat > .github/workflows/hex.yml <<'YAML'
name: "BIN → HEX exporter"

on:
  push:
    branches: ["main","master"]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  export-hex:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Install deps
        run: |
          set -euo pipefail
          python -m pip install --upgrade pip
          pip install intelhex pyyaml

      - name: Export BIN → HEX
        run: |
          set -euo pipefail
          python scripts/export_bins_to_hex.py

      - name: Verify 1:1 (BIN ↔ HEX)
        run: |
          set -euo pipefail
          BIN_COUNT=$(find rawdata -type f -path '*/validated/*' -iname '*.bin' | wc -l | tr -d ' ')
          HEX_COUNT=$(find dist/deepseek/incoming -type f -iname '*.hex' 2>/dev/null | wc -l | tr -d ' ' || echo 0)
          echo "BIN_COUNT=$BIN_COUNT"
          echo "HEX_COUNT=$HEX_COUNT"
          if [ "$BIN_COUNT" -gt 0 ] && [ "$HEX_COUNT" -lt "$BIN_COUNT" ]; then
            echo "::error ::Export produced fewer HEX files than BIN files ($HEX_COUNT < $BIN_COUNT)"
            exit 1
          fi
          echo "OK"

      - name: Upload HEX payload
        uses: actions/upload-artifact@v4
        with:
          name: deepseek-input-hex
          path: |
            dist/deepseek/incoming/**/*.hex
            dist/deepseek/incoming/**/*.json
            dist/deepseek/incoming/manifest-hex.csv
          if-no-files-found: ignore
YAML

git add .github/workflows/hex.yml
git commit -m "ci(hex): fix triggers; remove stray 'true:'"
git push
