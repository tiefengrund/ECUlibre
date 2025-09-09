# ECU Analysis (MED17) – GitHub Actions

Automatische Analyse von MED17 VR-BINs bei jedem Push. Ergebnisse als Artifacts (CSV, PNG, YAML).

## Quickstart
1. Lege deine `*.bin` in `bins/`.
2. (Optional) Analyzer-Image bauen & in GHCR pushen:

   ```bash
   export OWNER=tiefengrund
   export REPO=ECUlibre
   export IMAGE=ghcr.io/$OWNER/$REPO/med17-analyzer:latest

   echo $GHCR_TOKEN | docker login ghcr.io -u $OWNER --password-stdin
   docker build -t $IMAGE .
   docker push $IMAGE
   ```

3. Workflow läuft automatisch bei Änderungen unter `bins/**/*.bin`.

**Genutztes Image:** `ghcr.io/tiefengrund/ECUlibre/med17-analyzer:latest`
