# ECU Analysis – Anleitung (Deutsch)

## 1. Neue Datei hinzufügen
Lege dein neues VR-Dump `.bin`-File im Ordner `rawdata/` ab, z. B.:

rawdata/ECU_<modell>_<jahr><name>.bin

## 2. Präferenz wählen
Vor jedem Lauf muss klar sein, ob die Analyse mit Fokus auf:
- **power** → möglichst viel Leistung
- **smooth** → ruhiger schalten / komfortorientiert

laufen soll.

Möglichkeiten:

- **Commit-Message-Tag**:

- **Datei `prefs/mode`**:
```bash
echo smooth > prefs/mode
git add prefs/mode
git commit -m "set analysis preference"

reports/<BINNAME>/

README.de.md – Bericht auf Deutsch

README.en.md – Report in English

analysis_summary.yaml

entropy_plot.png

entropy_windows.csv

block_checksums.csv

maps_summary.csv
