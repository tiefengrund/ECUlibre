# ECUlibre – Versioning Concept

## English
### Project (Tools/Repo)
- SemVer `MAJOR.MINOR.PATCH` (e.g. `0.1.0`), tags `vX.Y.Z`, changelog via *Keep a Changelog*.
### Schema (Metadata)
- `schema_version` in each dataset, tags `schema-vX.Y`.
### Dataset (ECU Raw Packages)
- Validated raw + metadata + checksums; named `releases/datasets/.../dataset-vA.B.C.zip`.
### Patch-Packs (Feature Mods)
- Rules + scripts + tests; named `releases/patchpacks/.../<feature>-vA.B.C.zip`.
### Compatibility
- Map patch-pack ↔ dataset in `docs/compatibility.md`.
### Branching
- Trunk-based: `main` releasable; feature branches → PR → tag releases.

## Deutsch
### Projekt (Tools/Repo)
- SemVer `MAJOR.MINOR.PATCH` (z. B. `0.1.0`), Tags `vX.Y.Z`, Changelog nach *Keep a Changelog*.
### Schema (Metadaten)
- `schema_version` in jedem Datensatz, Schema-Tags `schema-vX.Y`.
### Datensatz (ECU-Rohpakete)
- Validierte Rohdaten + Metadaten + Prüfsummen; Name `releases/datasets/.../dataset-vA.B.C.zip`.
### Patch-Packs (Feature)
- Regeln + Skripte + Tests; Name `releases/patchpacks/.../<feature>-vA.B.C.zip`.
### Kompatibilität
- Zuordnung Patch-Pack ↔ Dataset in `docs/compatibility.md`.
### Branching
- Trunk-based: `main` releasbar; Feature-Branches → PR → Tags.

