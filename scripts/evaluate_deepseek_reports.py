#!/usr/bin/env python3
import os, sys, json, binascii
from pathlib import Path

ANN_DIR = Path("reports/china-boeller")
HEX_DIR = Path("dist/deepseek/incoming")
MIN_SCORE = int(os.getenv("MIN_SCORE", "60"))
FAIL_ON_LOW = os.getenv("FAIL_ON_LOW_SCORE", "0") == "1"
SUMMARY_PATH = os.getenv("GITHUB_STEP_SUMMARY")

def parse_hex_bytes(text: str) -> bytes:
    data = bytearray()
    for ln in text.splitlines():
        ln = ln.strip()
        if not ln.startswith(":"):
            continue
        try:
            reclen = int(ln[1:3], 16)
            rectyp = int(ln[7:9], 16)
            if rectyp == 0x00:
                bytestr = ln[9:9+2*reclen*2]
                data.extend(binascii.unhexlify(bytestr))
        except Exception:
            continue
    return bytes(data)

def eval_one(report_path: Path):
    try:
        rep = json.loads(report_path.read_text(encoding="utf-8"))
    except Exception as e:
        return {"file": report_path.name, "ok": False, "error": f"invalid json: {e}", "score": 0}

    file_name = Path(rep.get("file","")).name or report_path.stem + ".hex"
    hex_path = HEX_DIR / file_name
    if not hex_path.exists():
        return {"file": report_path.name, "ok": False, "error": f"missing HEX: {hex_path}", "score": 0}

    data = parse_hex_bytes(hex_path.read_text(encoding="utf-8", errors="ignore"))
    nbytes = len(data)

    summary = rep.get("summary","") or ""
    regions = rep.get("regions",[]) or []

    # validations
    invalid_addr = 0
    norm_regions = []
    for r in regions:
        try:
            s = int(r["start_addr"], 16)
            e = int(r["end_addr"], 16)
            if s > e or s < 0 or (nbytes and e >= nbytes):
                invalid_addr += 1
            norm_regions.append((s, e, str(r.get("label","region"))))
        except Exception:
            invalid_addr += 1

    # overlaps & coverage
    overlaps = 0
    covered = 0
    if norm_regions:
        norm_regions.sort(key=lambda x: (x[0], x[1]))
        merged = []
        cs, ce = norm_regions[0][0], norm_regions[0][1]
        for s,e,_ in norm_regions[1:]:
            if s <= ce:
                overlaps += 1
                ce = max(ce, e)
            else:
                merged.append((cs,ce))
                cs, ce = s, e
        merged.append((cs,ce))
        covered = sum((e - s + 1) for s,e in merged if e >= s)

    coverage_pct = (covered / nbytes * 100.0) if nbytes else 0.0

    # scoring
    score = 100
    issues = []
    if not summary.strip():
        score -= 10; issues.append("empty_summary")
    if not regions:
        score -= 30; issues.append("no_regions")
    if invalid_addr:
        score -= min(30, 10*invalid_addr); issues.append(f"invalid_addr:{invalid_addr}")
    if overlaps:
        score -= min(50, 10*overlaps); issues.append(f"overlaps:{overlaps}")
    if nbytes:
        if coverage_pct < 0.5:
            score -= 20; issues.append("very_low_coverage")
        elif coverage_pct < 2.0:
            score -= 10; issues.append("low_coverage")
        elif coverage_pct > 95.0:
            score -= 10; issues.append("suspiciously_high_coverage")

    score = max(0, min(100, score))
    ok = score >= MIN_SCORE and invalid_addr == 0

    return {
        "file": file_name,
        "report_json": report_path.name,
        "ok": ok,
        "score": score,
        "bytes": nbytes,
        "regions": len(regions),
        "overlaps": overlaps,
        "invalid_addr": invalid_addr,
        "coverage_pct": round(coverage_pct, 3),
        "issues": issues,
        "summary_len": len(summary.strip()),
        "hex_rel": str(hex_path),
        "eval_json": report_path.with_suffix(".eval.json").name
    }

def main():
    ann = sorted(ANN_DIR.glob("*.json"))
    if not ann:
        print("no reports to evaluate in reports/china-boeller", file=sys.stderr)
        return 0

    rows = []
    worst = 101
    for rp in ann:
        res = eval_one(rp)
        rows.append(res)
        # write eval json
        (ANN_DIR / res["eval_json"]).write_text(json.dumps(res, indent=2), encoding="utf-8")
        worst = min(worst, res["score"])

    # summary table
    hdr = "| file | score | ok | regions | overlaps | invalid_addr | coverage% | bytes |\n|---|---:|:---:|---:|---:|---:|---:|---:|\n"
    lines = [
        f"| {r['file']} | {r['score']} | {'✅' if r['ok'] else '❌'} | {r['regions']} | {r['overlaps']} | {r['invalid_addr']} | {r['coverage_pct']} | {r['bytes']} |"
        for r in rows
    ]
    md = "### DeepSeek evaluation\n" + hdr + "\n".join(lines) + "\n"
    print(md)
    if SUMMARY_PATH:
        with open(SUMMARY_PATH, "a", encoding="utf-8") as fh:
            fh.write(md)

    if FAIL_ON_LOW and any(not r["ok"] for r in rows):
        print("One or more reports below MIN_SCORE or with invalid addresses.", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
