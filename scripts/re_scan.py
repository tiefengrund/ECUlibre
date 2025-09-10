#!/usr/bin/env python3
# Reverse-Engineering Scanner (safe, read-only)
# - ASCII & UTF-16LE strings
# - Marker-Suche (Bosch/MED/MG1/UDS/XCP/ASAM/A2L/...)
# - Entropy-Segmente (4KiB Fenster) + Labels
# - Byte-Histogramm (PNG)
# - JSON/CSV Summary
import argparse, json, math, re, zlib
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

MARKERS = [
    b"BOSCH", b"MED", b"MG1", b"ME17", b"ME7",
    b"TRICORE", b"INFINEON", b"SIEMENS",
    b"ASAM", b"A2L", b"KWP", b"UDS", b"XCP", b"CAN",
    b"SWFL", b"SWUP", b"BOOT", b"CBOOT", b"FLASH", b"CAL", b"MAP"
]

def ascii_strings(b: bytes, minlen=4):
    out=[]; cur=[]
    for x in b:
        if 32 <= x < 127:
            cur.append(x)
        else:
            if len(cur) >= minlen: out.append(bytes(cur).decode('ascii','ignore'))
            cur=[]
    if len(cur) >= minlen: out.append(bytes(cur).decode('ascii','ignore'))
    return out

def utf16le_strings(b: bytes, minlen=4):
    out=[]; cur=[]
    # read 2-byte units
    for i in range(0, len(b)-1, 2):
        ch = int.from_bytes(b[i:i+2], 'little', signed=False)
        if 32 <= ch < 127:
            cur.append(ch)
        else:
            if len(cur) >= minlen: out.append("".join(map(chr, cur)))
            cur=[]
    if len(cur) >= minlen: out.append("".join(map(chr, cur)))
    return out

def shannon_entropy(arr_u8: np.ndarray):
    if arr_u8.size == 0: return 0.0
    counts = np.bincount(arr_u8, minlength=256)
    p = counts / float(arr_u8.size)
    nz = p[p>0]
    return float(-(nz*np.log2(nz)).sum())

def segment_entropy(b: bytes, win=4096):
    rows=[]
    arr = np.frombuffer(b, dtype=np.uint8)
    for off in range(0, len(b), win):
        chunk = arr[off:off+win]
        H = shannon_entropy(chunk)
        rows.append((off, len(chunk), H))
    df = pd.DataFrame(rows, columns=["offset","length","entropy_bits_per_byte"])
    # simple run-length merge into segments (adjacent windows with label)
    def label(h):
        return "low" if h<4.5 else ("med" if h<6.5 else "high")
    df["label"] = df["entropy_bits_per_byte"].apply(label)
    segs=[]
    start=0; cur_label=df.iloc[0]["label"] if not df.empty else "low"
    for i in range(len(df)):
        lab = df.iloc[i]["label"]
        if lab != cur_label:
            off0 = int(df.iloc[start]["offset"])
            off1 = int(df.iloc[i]["offset"])
            seg = arr[off0:off1]
            segs.append({"start":off0, "end":off1, "length":off1-off0,
                         "label":cur_label, "entropy_mean":float(df.iloc[start:i]["entropy_bits_per_byte"].mean())})
            start=i; cur_label=lab
    if not df.empty:
        off0 = int(df.iloc[start]["offset"])
        off1 = int(df.iloc[len(df)-1]["offset"] + df.iloc[len(df)-1]["length"])
        seg = arr[off0:off1]
        segs.append({"start":off0, "end":off1, "length":off1-off0,
                     "label":cur_label, "entropy_mean":float(df.iloc[start:]["entropy_bits_per_byte"].mean())})
    return df, pd.DataFrame(segs)

def find_markers(b: bytes):
    hits=[]
    for m in MARKERS:
        start=0
        while True:
            idx = b.find(m, start)
            if idx==-1: break
            hits.append({"marker": m.decode('ascii','ignore'), "offset": idx})
            start = idx+1
    # crude UTF-16LE marker search (letters + zero)
    for m in MARKERS:
        pat = b"".join(x.to_bytes(2,'little') for x in m)
        start=0
        while True:
            idx = b.find(pat, start)
            if idx==-1: break
            hits.append({"marker": m.decode('ascii','ignore')+"_utf16le", "offset": idx})
            start = idx+1
    return pd.DataFrame(hits)

def byte_histogram_png(arr_u8: np.ndarray, out_png: Path):
    counts = np.bincount(arr_u8, minlength=256)
    plt.figure()
    plt.bar(range(256), counts)
    plt.xlabel("Byte value")
    plt.ylabel("Count")
    plt.title("Byte frequency histogram")
    plt.tight_layout()
    plt.savefig(out_png)
    plt.close()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    p = Path(args.bin); out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    b = p.read_bytes()
    u8 = np.frombuffer(b, dtype=np.uint8)

    # Strings
    asc = ascii_strings(b, 4)
    (out/"strings_ascii.txt").write_text("\n".join(asc), encoding="utf-8")
    u16 = utf16le_strings(b, 4)
    (out/"strings_utf16le.txt").write_text("\n".join(u16), encoding="utf-8")

    # Markers
    dfm = find_markers(b)
    if not dfm.empty:
        dfm.sort_values(["marker","offset"]).to_csv(out/"markers.csv", index=False)
    (out/"markers.json").write_text(dfm.to_json(orient="records"), encoding="utf-8")

    # Entropy windows + segments
    dfw, segs = segment_entropy(b, 4096)
    dfw.to_csv(out/"entropy_windows_4k.csv", index=False)
    segs.to_csv(out/"segments.csv", index=False)

    # Histogram
    byte_histogram_png(u8, out/"byte_histogram.png")

    # Summary JSON
    summary = {
        "input": p.name,
        "size_bytes": len(b),
        "strings": {"ascii_count": len(asc), "utf16le_count": len(u16)},
        "markers_count": 0 if dfm is None or dfm.empty else int(len(dfm)),
        "segments": {"count": 0 if segs is None or segs.empty else int(len(segs))},
        "artifacts": {
            "strings_ascii": str((out/"strings_ascii.txt").as_posix()),
            "strings_utf16le": str((out/"strings_utf16le.txt").as_posix()),
            "markers_csv": str((out/"markers.csv").as_posix()),
            "markers_json": str((out/"markers.json").as_posix()),
            "entropy_windows_csv": str((out/"entropy_windows_4k.csv").as_posix()),
            "segments_csv": str((out/"segments.csv").as_posix()),
            "byte_histogram_png": str((out/"byte_histogram.png").as_posix())
        }
    }
    (out/"re_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps({"ok": True, "summary_path": str(out/"re_summary.json")}))
if __name__ == "__main__":
    main()
