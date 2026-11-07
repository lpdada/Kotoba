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
ZH_DIR = ROOT / "Tools" / "grammar_zh"


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


def load_zh() -> dict[str, dict]:
    """Hand-checked Chinese overlays, one file per level."""
    merged: dict[str, dict] = {}
    if ZH_DIR.is_dir():
        for path in sorted(ZH_DIR.glob("*.json")):
            merged.update(json.loads(path.read_text(encoding="utf-8")))
    return merged


def normalise(item: dict, level: str, zh: dict[str, dict]) -> dict:
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
        "meaning_zh": None,
        "notes_zh": None,
        "zh_status": "en-fallback",
    }
    if item.get("reading"):
        record["reading"] = item["reading"]

    overlay = zh.get(item["id"])
    if overlay:
        if overlay.get("meaning"):
            record["meaning_zh"] = overlay["meaning"]
        if overlay.get("notes"):
            record["notes_zh"] = overlay["notes"]
        example_zh = overlay.get("examples") or []
        for index, sentence in enumerate(example_zh):
            if index < len(record["examples"]):
                record["examples"][index]["zh"] = sentence
        # Status: checked = meaning + notes + every example; partial = meaning only path.
        all_examples = record["examples"] and all(x.get("zh") for x in record["examples"])
        if record["meaning_zh"] and record["notes_zh"] and all_examples:
            record["zh_status"] = "checked"
        elif record["meaning_zh"]:
            record["zh_status"] = "partial"
    return record


def main() -> int:
    records: list[dict] = []
    per_level: dict[str, int] = {}
    seen: set[str] = set()
    zh = load_zh()

    for level in LEVELS:
        items = fetch(level)
        per_level[level.upper()] = len(items)
        for item in items:
            key = f"{level}:{item['id']}"
            if key in seen:
                print(f"skip duplicate id: {key}", file=sys.stderr)
                continue
            seen.add(key)
            records.append(normalise(item, level, zh))

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
            "Chinese is produced by model batch translation from the OpenJLPT English source, "
            "checked item by item against the English; English is always kept. Items not yet "
            "translated keep meaning_zh=null with zh_status=en-fallback, so an untranslated "
            "entry is always marked rather than filled with guessed Chinese."
        ),
        "counts": counts,
        "chinese": {
            "meaning": sum(1 for r in records if r["meaning_zh"]),
            "notes": sum(1 for r in records if r["notes_zh"]),
            "examples": sum(1 for r in records for x in r["examples"] if x.get("zh")),
            "examples_total": sum(len(r["examples"]) for r in records),
            "checked": sum(1 for r in records if r["zh_status"] == "checked"),
            "partial": sum(1 for r in records if r["zh_status"] == "partial"),
            "en_fallback": sum(1 for r in records if r["zh_status"] == "en-fallback"),
        },
        "total": len(records),
        "entries": records,
    }
    OUT.write_text(json.dumps(document, ensure_ascii=False, indent=1), encoding="utf-8")

    print(f"wrote {OUT.relative_to(ROOT)}")
    for level in ["N5", "N4", "N3", "N2", "N1"]:
        print(f"  {level}: {counts.get(level, 0)}")
    print(f"  total: {len(records)}")
    chinese = document["chinese"]
    print(f"  zh meaning {chinese['meaning']}/{len(records)}, notes {chinese['notes']}/{len(records)}, examples {chinese['examples']}/{chinese['examples_total']}")
    print(f"  status checked {chinese['checked']}, partial {chinese['partial']}, en-fallback {chinese['en_fallback']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
