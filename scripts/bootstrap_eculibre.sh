# ... (oben unverändert: mk, writenew, append, slug)

# im großen while-Loop: NACH dem Trim eine slug bilden
for GEN in "${GENLIST[@]}"; do
  gen_trim="$(echo "$GEN" | sed -E 's/^ *| *$//g')"
  gen_slug="$(slug "$gen_trim")"     # << NEU: windows-sicherer Ordnername

  ECU_DIR="$DEFAULT_ECUVENDOR-$DEFAULT_ECUMODEL"
  FW_DIR="$DEFAULT_FW-$DEFAULT_REGION"

  # Ordner mit gen_slug statt gen_trim
  mk "$ROOT/rawdata/$BRAND/$MODEL/$gen_slug/$ECU_DIR/$FW_DIR"/{incoming,validated}
  mk "$ROOT/workbench/$BRAND/$MODEL/$gen_slug/$ECU_DIR/$FW_DIR"/{10_analysis,20_decode,30_mods,40_build,50_tests,90_package}

  METAPATH="$ROOT/rawdata/$BRAND/$MODEL/$gen_slug/$ECU_DIR/$FW_DIR/metadata.yml"
  writenew "$METAPATH" "\
schema_version: \"1.0\"
brand: \"$BRAND\"
model: \"$MODEL\"
generation: \"$gen_trim\"   # << Menschlich lesbar in den Metadaten
ecu_vendor: \"$DEFAULT_ECUVENDOR\"
ecu_model: \"$DEFAULT_ECUMODEL\"
firmware: \"$DEFAULT_FW\"
region: \"$DEFAULT_REGION\"
hashes:
  raw_sha256: \"\"
  size_bytes: 0
notes: \"\"
"

  # Doku/Index: Anzeige = gen_trim, Path = gen_slug
  RELPATH="rawdata/${BRAND}/${MODEL}/${gen_slug}"
  ROW="| ${BRAND} | ${MODEL} | ${gen_trim} | ${ALIASES:-} | \`${RELPATH}\` |"
  grep -Fqx "$ROW" "$ROOT/docs/vehicle-index.md" 2>/dev/null || append "$ROOT/docs/vehicle-index.md" "$ROW"

  BROW="| ${MODEL} | ${gen_trim} | ${ALIASES:-} | \`${RELPATH}\` |"
  grep -Fqx "$BROW" "$BRAND_MD" 2>/dev/null || append "$BRAND_MD" "$BROW"
done
