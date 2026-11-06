#!/usr/bin/env python3
"""Build Kotoba/Resources/Grammar.json from OpenJLPT's grammar dataset.

Source : evanclan/OpenJLPT  →  data/json/grammar/n{1..5}.json
Licence: CC BY-SA 4.0 (repository LICENSE; same terms as Kotoba's Dictionary.json)
Pinned : commit bf4e1eecd5d11406aaecdee910464507aef7fcdc (n5.json, 2026-09-30)

Chinese policy (mirrors ATTRIBUTION.md):
  * OpenJLPT ships English meanings and English example translations only.
  * `meaning_zh` is therefore null and `zh_status` is "en-fallback" for every
    item — nothing is machine-translated or invented.
  * Surfacing Chinese later requires a hand-checked gloss per item.

Writes exactly one file: Kotoba/Resources/Grammar.json
"""
from __future__ import annotations

import json
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

COMMIT = "bf4e1eecd5d11406aaecdee910464507aef7fcdc"
SOURCE_REPO = "evanclan/OpenJLPT"
SOURCE_PATH = "data/json/grammar/{level}.json"
SOURCE_LICENSE = "CC BY-SA 4.0"
LEVELS = ["n5", "n4", "n3", "n2", "n1"]
MAX_EXAMPLES = 3

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Kotoba" / "Resources" / "Grammar.json"


def fetch(level: str) -> list[dict]:
    url = (
        f"https://raw.githubusercontent.com/{SOURCE_REPO}/{COMMIT}/"
        + SOURCE_PATH.format(level=level)
    )
    with urllib.request.urlopen(url, timeout=60) as response:
        payload = json.load(response)
    if isinstance(payload, dict):
        payload = payload.get("grammar") or payload.get("entries") or []
    if not isinstance(payload, list) or not payload:
        raise SystemExit(f"unexpected payload for {level}: {type(payload)}")
    return payload


def normalise(item: dict, level: str) -> dict:
    """Copy OpenJLPT fields verbatim; only rename and select, never rewrite."""
    record = {
        "id": item["id"],
        "level": item.get("level", level.upper()),
        "pattern": item.get("pattern", ""),
        "romaji": item.get("romaji", ""),
        "meaning_en": item.get("meaning", ""),
        "formation": item.get("formation", ""),
        "notes_en": item.get("notes", ""),
        "tags": item.get("tags") or [],
        "examples": (item.get("examples") or [])[:MAX_EXAMPLES],
        # Chinese is intentionally absent rather than machine-translated.
        "meaning_zh": None,
        "zh_status": "en-fallback",
    }
    if item.get("reading"):
        record["reading"] = item["reading"]
    return record


def main() -> int:
    records: list[dict] = []
    per_level: dict[str, int] = {}
    seen: set[str] = set()

    for level in LEVELS:
        items = fetch(level)
        per_level[level.upper()] = len(items)
        for item in items:
            key = f"{level}:{item['id']}"
            if key in seen:
                print(f"skip duplicate id: {key}", file=sys.stderr)
                continue
            seen.add(key)
            records.append(normalise(item, level))

    counts: dict[str, int] = {}
    for record in records:
        counts[record["level"]] = counts.get(record["level"], 0) + 1

    document = {
        "version": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "license": SOURCE_LICENSE,
        "source": {
            "name": "OpenJLPT",
            "repo": SOURCE_REPO,
            "commit": COMMIT,
            "paths": [SOURCE_PATH.format(level=l) for l in LEVELS],
        },
        "translationPolicy": (
            "OpenJLPT provides English meanings and English example translations only; "
            "meaning_zh stays null and zh_status is en-fallback. No machine translation."
        ),
        "counts": counts,
        "total": len(records),
        "entries": records,
    }
    OUT.write_text(json.dumps(document, ensure_ascii=False, indent=1), encoding="utf-8")

    print(f"wrote {OUT.relative_to(ROOT)}")
    for level in ["N5", "N4", "N3", "N2", "N1"]:
        print(f"  {level}: {counts.get(level, 0)}")
    print(f"  total: {len(records)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
