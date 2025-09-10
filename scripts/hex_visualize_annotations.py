#!/usr/bin/env python3
import json, html, binascii
from pathlib import Path

IN_DIR = Path("dist/deepseek/incoming")
ANN_DIR = Path("reports/deepseek")
OUT_DIR = ANN_DIR

def parse_hex_lines(text):
    data = bytearray()
    for ln in text.splitlines():
        if not ln.startswith(":"): continue
        try:
            reclen = int(ln[1:3], 16)
            addr   = int(ln[3:7], 16)
            rectyp = int(ln[7:9], 16)
            if rectyp == 0x00:  # data
                bytestr = ln[9:9+2*reclen]
                data.extend(binascii.unhexlify(bytestr))
        except Exception:
            continue
    return bytes(data)

def highlight(data: bytes, regions):
    # regions: [{"start_addr":"0x..","end_addr":"0x..","label": "..."}]
    marks = {}
    for r in regions:
        try:
            s = int(r["start_addr"], 16); e = int(r["end_addr"],16)
            for i in range(max(0,s), min(len(data), e+1)):
                marks[i] = r.get("label","region")
        except Exception:
            pass
    rows=[]
    for i in range(0, len(data), 16):
        chunk=data[i:i+16]
        hexpart=" ".join(f"{b:02X}" for b in chunk)
        asc="".join(chr(b) if 32<=b<127 else "." for b in chunk)
        # wrap spans
        def span(j,b):
            lab = marks.get(i+j)
            if lab:
                return f'<span class="mark" title="{html.escape(lab)}">{b:02X}</span>'
            return f"{b:02X}"
        hexspan=" ".join(span(j,b) for j,b in enumerate(chunk))
        rows.append(f"<tr><td>0x{i:08X}</td><td class='hex'>{hexspan}</td><td>{html.escape(asc)}</td></tr>")
    return "\n".join(rows)

def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for ann in sorted(ANN_DIR.glob("*.json")):
        meta = json.loads(ann.read_text(encoding="utf-8"))
        # read original HEX text
        hex_path = IN_DIR / Path(meta["file"]).name
        if not hex_path.exists():
            continue
        text = hex_path.read_text(encoding="utf-8", errors="ignore")
        data = parse_hex_lines(text)
        table = highlight(data, meta.get("regions",[]))
        html_out = f"""<!doctype html>
<html><head><meta charset="utf-8">
<title>{html.escape(hex_path.name)} – DeepSeek annotations</title>
<style>
body{{font-family:ui-monospace,Consolas,monospace}}
table{{border-collapse:collapse;width:100%}}
td{{border-bottom:1px solid #eee;padding:2px 6px;vertical-align:top}}
td.hex{{white-space:pre}}
.mark{{background: #ffe08a; border-radius:3px; padding:1px 2px}}
summary{{font-weight:600}}
</style></head>
<body>
<h1>{html.escape(hex_path.name)}</h1>
<details open><summary>Summary</summary><pre>{html.escape(meta.get("summary",""))}</pre></details>
<h2>Hexdump (regions highlighted)</h2>
<table>
<tr><th>Offset</th><th>Hex</th><th>ASCII</th></tr>
{table}
</table>
</body></html>"""
        out = OUT_DIR / (hex_path.stem + ".html")
        out.write_text(html_out, encoding="utf-8")
        print(f"html: {out}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
