#!/usr/bin/env python3
"""Build Kotoba/Resources/SampleClips.json.

Deterministic: same inputs -> byte-identical output (no timestamps, no randomness).

Sources (never invented Japanese):
  * grammar examples  — Kotoba/Resources/Grammar.json (OpenJLPT, CC BY-SA 4.0)
  * dictionary examples — Kotoba/Resources/Dictionary.json (JMdict/OpenJLPT, CC BY-SA 4.0)
  * the 10 handcrafted clips already in SampleClips.json are preserved as-is

Each generated clip is one group of up to 5 consecutive example sentences from a
single level, so every line is traceable to a source record.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "Kotoba" / "Resources"
GRAMMAR = RES / "Grammar.json"
DICTIONARY = RES / "Dictionary.json"
OUT = RES / "SampleClips.json"

LEVELS = ["n5", "n4", "n3", "n2", "n1"]
LINES_PER_CLIP = 5
MIN_CLIPS_PER_LEVEL = 30
CHARS_PER_SECOND = 5.5
MIN_LINE_SECONDS = 2.0


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def grammar_sentences(grammar: dict) -> dict[str, list[dict]]:
    """[{ja, en, zh, source_id, pattern, tags}] per level, in file order."""
    by_level: dict[str, list[dict]] = {level: [] for level in LEVELS}
    for entry in grammar["entries"]:
        level = (entry.get("level") or "").lower()
        if level not in by_level:
            continue
        for example in entry.get("examples") or []:
            ja = (example.get("ja") or "").strip()
            if not ja:
                continue
            by_level[level].append(
                {
                    "ja": ja,
                    "en": (example.get("en") or "").strip(),
                    "zh": (example.get("zh") or "").strip(),
                    "source_id": entry["id"],
                    "pattern": entry.get("pattern", ""),
                    "tags": entry.get("tags") or [],
                }
            )
    return by_level


def dictionary_sentences(dictionary: dict) -> dict[str, list[dict]]:
    """Fallback pool so every level can reach the minimum clip count."""
    by_level: dict[str, list[dict]] = {level: [] for level in LEVELS}
    entries = dictionary["entries"] if isinstance(dictionary, dict) else dictionary
    for entry in entries:
        level = (entry.get("lv") or "").lower()
        if level not in by_level:
            continue
        for example in entry.get("ex") or []:
            ja = (example.get("ja") or "").strip()
            if not ja:
                continue
            by_level[level].append(
                {
                    "ja": ja,
                    "en": (example.get("en") or "").strip(),
                    "zh": "",
                    "source_id": entry.get("id", ""),
                    "pattern": entry.get("w", ""),
                    "tags": [],
                }
            )
    return by_level


def duration_for(text: str) -> int:
    seconds = max(len(text) / CHARS_PER_SECOND, MIN_LINE_SECONDS)
    return max(int(round(seconds)), 1)


def make_clips(level: str, sentences: list[dict], start_index: int, source: str) -> list[dict]:
    clips = []
    for group_index in range(0, len(sentences), LINES_PER_CLIP):
        group = sentences[group_index : group_index + LINES_PER_CLIP]
        if not group:
            continue
        index = start_index + group_index // LINES_PER_CLIP
        timings = []
        cursor = 0.0
        for sentence in group:
            length = duration_for(sentence["ja"])
            timings.append({"start": round(cursor, 2), "end": round(cursor + length, 2)})
            cursor += length
        has_zh = all(sentence["zh"] for sentence in group)
        pattern = group[0]["pattern"]
        title = f"{level.upper()} 语法例句 {index + 1}"
        if pattern:
            title += f" · {pattern}"
        topics = ["语法例句"] + [tag for tag in group[0]["tags"][:2]]
        clips.append(
            {
                "id": f"gclip-{level}-{index + 1:03d}",
                "title": title,
                "series": f"{level.upper()} 例句",
                "episode": f"第 {index + 1} 组",
                "transcript": "\n".join(sentence["ja"] for sentence in group),
                "translation": "\n".join(sentence["zh"] for sentence in group) if has_zh else "",
                "translation_en": "\n".join(sentence["en"] for sentence in group),
                "level": level,
                "topics": topics,
                "duration_seconds": int(round(cursor)),
                "line_timings": timings,
                "media": {"kind": "generated"},
                "attribution": source,
                "custom": False,
            }
        )
    return clips


def main() -> int:
    grammar = load(GRAMMAR)
    dictionary = load(DICTIONARY)
    existing = load(OUT)["clips"]

    pools = grammar_sentences(grammar)
    fallback = dictionary_sentences(dictionary)

    generated: list[dict] = []
    per_level: dict[str, int] = {}
    for level in LEVELS:
        sentences = pools[level]
        source = "OpenJLPT 例句（CC BY-SA 4.0）"
        clips = make_clips(level, sentences, 0, source)
        if len(clips) < MIN_CLIPS_PER_LEVEL:
            # Top up from the dictionary pool, still real sentences.
            extra = make_clips(level, fallback[level], len(clips), "JMdict 例句（CC BY-SA 4.0）")
            clips = (clips + extra)[: max(MIN_CLIPS_PER_LEVEL, len(clips))]
        per_level[level] = len(clips)
        generated.extend(clips)

    clips = existing + generated
    document = {
        "version": 2,
        "generatedBy": "Tools/build_clips.py",
        "counts": {"total": len(clips), "perLevel": per_level, "handcrafted": len(existing)},
        "clips": clips,
    }
    OUT.write_text(json.dumps(document, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    print(f"wrote {OUT.relative_to(ROOT)}")
    for level in LEVELS:
        print(f"  {level.upper()}: {per_level[level]}")
    print(f"  handcrafted: {len(existing)}")
    print(f"  total: {len(clips)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
