#!/usr/bin/env python3
import os, json, time, textwrap, re, sys
from pathlib import Path
import requests

BASE_URL = os.getenv("DEEPSEEK_BASE_URL", "https://api.deepseek.com")
API_KEY  = os.getenv("DEEPSEEK_API_KEY", "")
MODEL    = os.getenv("DEEPSEEK_MODEL", "deepseek-reasoner")  # oder deepseek-chat
IN_DIR   = Path("dist/deepseek/incoming")
OUT_DIR  = Path("reports/china-boeller")
CHUNK_CHARS = 180000  # < 128k Tokens bleibt safe; konservativ splitten

if not API_KEY:
    print("DEEPSEEK_API_KEY missing", file=sys.stderr); sys.exit(2)

SYSTEM = (
  "You are an ECU firmware data annotator. The user will send Intel HEX text chunks.\n"
  "Task: Return ONLY JSON. Do not propose any modifications.\n"
  "Produce:\n"
  "{\n"
  '  "file": "<name>",\n'
  '  "summary": "high-level notes (no advice on disabling safety)",\n'
  '  "regions": [\n'
  '     {"label":"candidate_header","start_addr":"0x...","end_addr":"0x..."},\n'
  '     {"label":"calibration_table?","start_addr":"0x...","end_addr":"0x..."}\n'
  '  ],\n'
  '  "hashes": {"hex_lines": <int>}\n'
  "}\n"
)

def call_ds(messages, max_tokens=1000, retries=3):
    url = f"{BASE_URL}/chat/completions"
    headers = {"Authorization": f"Bearer {API_KEY}", "Content-Type":"application/json"}
    body = {"model": MODEL, "messages": messages,
            "response_format":{"type":"json_object"},
            "max_tokens": max_tokens}
    for i in range(retries):
        r = requests.post(url, headers=headers, json=body, timeout=120)
        if r.status_code == 200:
            try:
                content = r.json()["choices"][0]["message"]["content"]
                return json.loads(content)
            except Exception:
                time.sleep(2); continue
        elif r.status_code in (429, 500, 503):
            time.sleep(2*(i+1)); continue
        else:
            raise RuntimeError(f"DeepSeek error {r.status_code}: {r.text[:500]}")
    raise RuntimeError("DeepSeek no valid JSON after retries")

def chunk_text(t, size):
    for i in range(0, len(t), size):
        yield t[i:i+size], i//size+1, (len(t)+size-1)//size

def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    hex_files = sorted(IN_DIR.rglob("*.hex"))
    if not hex_files:
        print("No HEX inputs in dist/deepseek/incoming", file=sys.stderr)
        return 0

    for hp in hex_files:
        txt = hp.read_text(encoding="utf-8", errors="ignore")
        # Basic sanity: keep only Intel HEX lines
        lines = [ln for ln in txt.splitlines() if ln.strip().startswith(":")]
        payload = "\n".join(lines)
        merged = {"file": str(hp), "summary": "", "regions": [], "hashes":{"hex_lines": len(lines)}}

        # First chunk asks for global summary; subsequent chunks may add regions
        for chunk, idx, total in chunk_text(payload, CHUNK_CHARS):
            user = (
              f"FILE: {hp.name}\n"
              f"CHUNK {idx}/{total}\n"
              "CONTENT (Intel HEX lines):\n" + chunk
            )
            messages = [
                {"role":"system", "content": SYSTEM},
                {"role":"user", "content": user}
            ]
            js = call_ds(messages, max_tokens=1500)
            # merge conservatively
            if "summary" in js and js["summary"]:
                merged["summary"] = js["summary"][:5000]
            if "regions" in js:
                for r in js["regions"]:
                    if isinstance(r, dict) and "start_addr" in r and "end_addr" in r:
                        merged["regions"].append(r)

        outp = OUT_DIR / (hp.stem + ".json")
        outp.write_text(json.dumps(merged, indent=2), encoding="utf-8")
        print(f"annotated: {hp} -> {outp}")

    return 0

if __name__ == "__main__":
    sys.exit(main())
