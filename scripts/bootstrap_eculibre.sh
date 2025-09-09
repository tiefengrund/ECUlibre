#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"   # Zielverzeichnis (Default: aktuelles)

# ===== Helper =====
mk()        { mkdir -p "$@"; }
writenew()  { [[ -f "$1" ]] || printf "%s\n" "${2:-}" > "$1"; }
append()    { printf "%s\n" "${2:-}" >> "$1"; }
slug() {
  # lower-case, ersetze Leerzeichen/.,(),/ -> '-' ; entferne Nicht-[a-z0-9_-] ; reduziere Mehrfach-'-'
  tr '[:upper:]' '[:lower:]' <<<"$1" \
  | sed -E 's/[ .()\/]+/-/g' \
  | sed -E 's/[^a-z0-9_-]//g' \
  | sed -E 's/-{2,}/-/g' \
  | sed -E 's/^-+|-+$//g'
}

# ===== Manifest: Brand|Model|Generation/Platform(;/…)|Aliases(comma)|Notes =====
VEHICLES="$(cat <<'EOF'
Audi|A3|8V / MQB|Typ8V,MQB|
Audi|A4|B9 (Typ 8W)|B9|
Audi|A6|C5 (Typ 4B); C6 (4F); C7 (4G); C8 (4K)|4B,4F,4G,4K|Generationen und Typcodes
Audi|A7|C8|C8|
Audi|Q5|FY (MLB evo)|FY,MLB-evo|
Audi|Q7|4M (MLB evo)|4M,MLB-evo|
BMW|1er|F20/F21|F20,F21|
BMW|3er|G20|G20|
BMW|5er|G30/G31|G30,G31|
BMW|X3|G01|G01|
Mercedes|C-Klasse|W205; W206|W205,W206|
Mercedes|E-Klasse|W213|W213|
Mercedes|GLC|X253|X253|
Volkswagen|Golf|Mk7 / MQB|Mk7,MQB|
Volkswagen|Passat|B8 (MQB)|B8,MQB|
Volkswagen|Tiguan|AD / MQB|AD,MQB|
Skoda|Octavia|Mk4 (NX, MQB)|NX,Mk4,MQB|
Seat|Leon|Mk4 (KL, MQB)|KL,Mk4,MQB|
Opel|Astra|K|AstraK|
Opel|Insignia|B|InsigniaB|
Ford|Focus|Mk4 (C2)|Mk4,C2|
Ford|Mondeo|Mk5 (CD4)|Mk5,CD4|
Renault|Clio|V (CMF-B)|ClioV,CMF-B|
Renault|Megane|IV (CMF-C/D)|MeganeIV,CMF-CD|
Peugeot|308|T9|T9|
Citroen|C4|B7|B7|
Fiat|500|312|312|
Toyota|Corolla|E210 (TNGA-C)|E210,TNGA|
Honda|Civic|FK7/FK8 (10th Gen)|FK7,FK8|
Mazda|3|BP|BP|
Nissan|Qashqai|J11|J11|
Hyundai|i30|PD|PD|
Kia|Ceed|CD|CD|
Volvo|XC60|SPA|SPA|
Tesla|Model 3|Highland (2023–)|Highland,Model3|
Subaru|Forester|SK|SK|
Mitsubishi|Outlander|GF/GM; GN|GF,GM,GN|
Alfa Romeo|Giulia|952 (Giorgio)|952,Giorgio|
Dacia|Duster|J11/J12|J11,J12|
EOF
)"

# ===== Defaults für ECU-Struktur =====
DEFAULT_ECUVENDOR="Bosch"
DEFAULT_ECUMODEL="MD1"
DEFAULT_FW="FW0001"
DEFAULT_REGION="EU"

# ===== Top-Level Grundgerüst =====
mk "$ROOT"/{docs,schemas,rawdata,workbench,patches,releases,tools,ci,scripts,logo,docs/brands}
writenew "$ROOT/VERSION" "0.1.0"
writenew "$ROOT/CHANGELOG.md" "# Changelog

All notable changes to this project will be documented here.
"

# Metadatenschema
writenew "$ROOT/schemas/metadata.schema.yaml" "\
\$schema: \"https://json-schema.org/draft/2020-12/schema\"
type: object
required: [schema_version, brand, model, generation, ecu_vendor, ecu_model, firmware, region, hashes]
properties:
  schema_version: { type: string }
  brand: { type: string }
  model: { type: string }
  generation: { type: string }
  ecu_vendor: { type: string }
  ecu_model: { type: string }
  firmware: { type: string }
  region: { type: string }
  notes: { type: string }
  hashes:
    type: object
    properties:
      raw_sha256: { type: string }
      size_bytes: { type: integer }
"

# Beispiel-Patch
mk "$ROOT/patches/common/lane_assist_disable/tests"
writenew "$ROOT/patches/common/lane_assist_disable/README.md" "# Lane Assist Disable (common rules)
Intent: disable lane keeping assist in compliant ECUs (for research/education).
"
writenew "$ROOT/patches/common/lane_assist_disable/rules.yml" "\
patch_name: lane_assist_disable
semver: 0.1.0
description: Disable lane keeping assist (LKAS/LKA).
requires:
  schema: \">=1.0 <2.0\"
  ecu_vendor: \"*\"
  ecu_model: \"*\"
  firmware: \"*\"
rules:
  - match: { feature: 'lane_assist' }
    action: disable
tests: []
"

# ===== VERSIONS.md (EN → DE, kurz) =====
writenew "$ROOT/VERSIONS.md" "\
# ECUlibre – Versioning Concept

## English
### Project (Tools/Repo)
- SemVer \`MAJOR.MINOR.PATCH\` (e.g. \`0.1.0\`), tags \`vX.Y.Z\`, changelog via *Keep a Changelog*.
### Schema (Metadata)
- \`schema_version\` in each dataset, tags \`schema-vX.Y\`.
### Dataset (ECU Raw Packages)
- Validated raw + metadata + checksums; named \`releases/datasets/.../dataset-vA.B.C.zip\`.
### Patch-Packs (Feature Mods)
- Rules + scripts + tests; named \`releases/patchpacks/.../<feature>-vA.B.C.zip\`.
### Compatibility
- Map patch-pack ↔ dataset in \`docs/compatibility.md\`.
### Branching
- Trunk-based: \`main\` releasable; feature branches → PR → tag releases.

## Deutsch
### Projekt (Tools/Repo)
- SemVer \`MAJOR.MINOR.PATCH\` (z. B. \`0.1.0\`), Tags \`vX.Y.Z\`, Changelog nach *Keep a Changelog*.
### Schema (Metadaten)
- \`schema_version\` in jedem Datensatz, Schema-Tags \`schema-vX.Y\`.
### Datensatz (ECU-Rohpakete)
- Validierte Rohdaten + Metadaten + Prüfsummen; Name \`releases/datasets/.../dataset-vA.B.C.zip\`.
### Patch-Packs (Feature)
- Regeln + Skripte + Tests; Name \`releases/patchpacks/.../<feature>-vA.B.C.zip\`.
### Kompatibilität
- Zuordnung Patch-Pack ↔ Dataset in \`docs/compatibility.md\`.
### Branching
- Trunk-based: \`main\` releasbar; Feature-Branches → PR → Tags.
"

# ===== README.md (kurz, EN → DE, mit Links) =====
writenew "$ROOT/README.md" "\
# ECUlibre

## English (short)
Open-source workspace for **ECU research** on EU-mandated functions (e.g., lane keeping).  
**Purpose:** analyze raw ECU files, study feature flags, and build reproducible patch packs.  
**⚠️ Disclaimer:** Educational & research only; local laws/safety rules apply.

- Start: \`docs/vehicle-index.md\`
- Versioning: \`VERSIONS.md\`
- Brand pages: \`docs/brands/\`
- Patches (examples): \`patches/common\`
- Contribute: \`CONTRIBUTING.md\` (TBD)

## Deutsch (kurz)
Open-Source-Arbeitsbereich für **ECU-Forschung** zu EU-Funktionen (z. B. Spurhalteassistent).  
**Zweck:** Roh-ECU-Dateien analysieren, Feature-Schalter untersuchen, reproduzierbare Patch-Packs bauen.  
**⚠️ Hinweis:** Nur Forschung/Lernen; Gesetze/Sicherheitsregeln beachten.

- Einstieg: \`docs/vehicle-index.md\`
- Versionierung: \`VERSIONS.md\`
- Marken-Seiten: \`docs/brands/\`
- Patches (Beispiele): \`patches/common\`
- Mitmachen: \`CONTRIBUTING.md\` (TBD)
"

# ===== Vehicle Index initialisieren (nur Header) =====
writenew "$ROOT/docs/vehicle-index.md" "# Vehicle Index / Fahrzeug-Index

| Brand | Model | Generation/Platform | Aliases | Path |
|------:|:----- |:--------------------|:------- |:---- |
"
writenew "$ROOT/docs/vehicle-manifest.csv" "brand,model,generation_or_platform,aliases,notes"

# ===== Pro Eintrag: Struktur + Doku (idempotent) =====
while IFS='|' read -r BRAND MODEL GENPLAT ALIASES NOTES; do
  [[ -z "${BRAND// }" ]] && continue

  bslug="$(slug "$BRAND")"
  BRAND_DOC_DIR="$ROOT/docs/brands/$bslug"
  BRAND_MD="$BRAND_DOC_DIR/README.md"
  if [[ ! -f "$BRAND_MD" ]]; then
    mk "$BRAND_DOC_DIR"
    printf "# %s\n\n| Model | Generation/Platform | Aliases | Path |\n|:----- |:--------------------|:------- |:---- |\n" "$BRAND" > "$BRAND_MD"
  fi

  mk "$ROOT/rawdata/$BRAND/$MODEL" "$ROOT/workbench/$BRAND/$MODEL"

  IFS=';' read -r -a GENLIST <<< "$GENPLAT"
  [[ ${#GENLIST[@]} -eq 0 ]] && GENLIST=("GEN")

  for GEN in "${GENLIST[@]}"; do
    gen_trim="$(echo "$GEN" | sed -E 's/^ *| *$//g')"
    ECU_DIR="$DEFAULT_ECUVENDOR-$DEFAULT_ECUMODEL"
    FW_DIR="$DEFAULT_FW-$DEFAULT_REGION"

    mk "$ROOT/rawdata/$BRAND/$MODEL/$gen_trim/$ECU_DIR/$FW_DIR"/{incoming,validated}
    mk "$ROOT/workbench/$BRAND/$MODEL/$gen_trim/$ECU_DIR/$FW_DIR"/{10_analysis,20_decode,30_mods,40_build,50_tests,90_package}

    METAPATH="$ROOT/rawdata/$BRAND/$MODEL/$gen_trim/$ECU_DIR/$FW_DIR/metadata.yml"
    writenew "$METAPATH" "\
schema_version: \"1.0\"
brand: \"$BRAND\"
model: \"$MODEL\"
generation: \"$gen_trim\"
ecu_vendor: \"$DEFAULT_ECUVENDOR\"
ecu_model: \"$DEFAULT_ECUMODEL\"
firmware: \"$DEFAULT_FW\"
region: \"$DEFAULT_REGION\"
hashes:
  raw_sha256: \"\"
  size_bytes: 0
notes: \"\"
"

    RELPATH="rawdata/${BRAND}/${MODEL}/${gen_trim}"
    ROW="| ${BRAND} | ${MODEL} | ${gen_trim} | ${ALIASES:-} | \`${RELPATH}\` |"
    grep -Fqx "$ROW" "$ROOT/docs/vehicle-index.md" 2>/dev/null || append "$ROOT/docs/vehicle-index.md" "$ROW"

    BROW="| ${MODEL} | ${gen_trim} | ${ALIASES:-} | \`${RELPATH}\` |"
    grep -Fqx "$BROW" "$BRAND_MD" 2>/dev/null || append "$BRAND_MD" "$BROW"
  done

  CSVLINE="\"$BRAND\",\"$MODEL\",\"$GENPLAT\",\"$ALIASES\",\"${NOTES:-}\""
  grep -Fqx "$CSVLINE" "$ROOT/docs/vehicle-manifest.csv" 2>/dev/null || append "$ROOT/docs/vehicle-manifest.csv" "$CSVLINE"
done <<< "$VEHICLES"

# ===== CONTRIBUTING & Compatibility-Seite =====
writenew "$ROOT/CONTRIBUTING.md" "# Contributing

- Add vehicles via \`docs/vehicle-manifest.csv\` (Brand|Model|Generation/Platform|Aliases|Notes).
- Re-run \`scripts/bootstrap_eculibre.sh\` to (re)generate structure and docs (idempotent).
- Validate metadata against \`schemas/metadata.schema.yaml\`.
"
writenew "$ROOT/docs/compatibility.md" "# Compatibility Matrix

> Map patch-pack versions to dataset tags here.
"

echo "✅ ECUlibre bootstrap complete at: $ROOT"
