#!/usr/bin/env python3
"""Structural accessibility checks that can run without Xcode.

Not a substitute for VoiceOver or Dynamic Type on a device: it verifies that the
codebase keeps the *invariants* this round established —
  * no fixed point sizes in views (everything goes through Theme.font / scaledFont),
  * font helpers really use text styles / @ScaledMetric,
  * interactive controls carry labels,
  * charts expose values,
  * colour-only state has a second channel,
  * Reduce Motion is honoured in the animated surfaces.
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Kotoba")
VIEWS = os.path.join(ROOT, "Views")
APP = os.path.join(ROOT, "App")
THEME = os.path.join(VIEWS, "Components", "Theme.swift")

problems = []


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def swift_files(*roots):
    for base in roots:
        for current, _dirs, files in os.walk(base):
            for name in sorted(files):
                if name.endswith(".swift"):
                    yield os.path.join(current, name)


theme = read(THEME)
if not re.search(r"func font\(\s*size:\s*CGFloat", theme):
    problems.append("Theme.font(size:) helper is missing")
if "struct ScaledFontModifier" not in theme or "func scaledFont(" not in theme:
    problems.append("scaledFont modifier is missing")
if "FontScale.textStyle(for:" not in theme:
    problems.append("Theme.font(size:) does not map through FontScale")
if "@ScaledMetric" not in theme:
    problems.append("ScaledFontModifier does not use @ScaledMetric")
if "func stateUnderline(" not in theme:
    problems.append("non-colour state helper (stateUnderline) is missing")

# 1. No fixed point sizes outside Theme.swift
for path in swift_files(VIEWS, APP):
    if os.path.abspath(path) == os.path.abspath(THEME):
        continue
    text = read(path)
    for match in re.finditer(r"\.system\(size:", text):
        line = text[: match.start()].count("\n") + 1
        problems.append(f"{os.path.relpath(path, ROOT)}:{line}: hardcoded .system(size:)")

# 2. Interactive controls carry accessibility information.
#    Text-titled buttons get their label from the title; only glyph-only buttons
#    need an explicit annotation, which is what we check here.
button_total = 0
for path in swift_files(VIEWS, APP):
    text = read(path)
    button_total += len(re.findall(r"\bButton\s*(\(|\{)", text))
    for match in re.finditer(r"\bButton\s*\{", text):
        depth = 0
        end = match.start()
        for index in range(match.start(), len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    end = index
                    break
        block = text[match.start(): end + 1]
        glyph_only = "Image(systemName:" in block and "Text(" not in block and "Label(" not in block
        if not glyph_only:
            continue
        tail = text[end + 1: end + 700]
        if not re.search(r"accessibilityLabel|a11yButton|accessibilityElement", tail):
            line = text[: match.start()].count("\n") + 1
            problems.append(f"{os.path.relpath(path, ROOT)}:{line}: glyph-only Button without accessibilityLabel")
if button_total < 50:
    problems.append(f"suspiciously few buttons counted ({button_total})")

# 3. Charts / progress surfaces expose values
for name, pattern in [
    ("ProgressScreen.swift", r"accessibilityValue"),
    ("ReviewView.swift", r"accessibilityValue"),
    ("CommonViews.swift", r"accessibilityValue"),
]:
    path = next((p for p in swift_files(VIEWS) if p.endswith(name)), None)
    if path is None or not re.search(pattern, read(path)):
        problems.append(f"{name}: chart/progress accessibility value missing")

# 4. Colour-only state has a second channel
if "stateUnderline" not in read(os.path.join(VIEWS, "Feed", "SubtitleView.swift")):
    problems.append("SubtitleView: familiarity colour has no second channel")
common = read(os.path.join(VIEWS, "Components", "CommonViews.swift"))
if "familiarityTitle" not in common:
    problems.append("FamiliarityBadge does not read the level out as text")
if "level!.label" not in common and "level?.label" not in common:
    problems.append("LevelBadge does not expose the level as text")
if not re.search(r"rating\.title", read(os.path.join(VIEWS, "Review", "ReviewView.swift"))):
    problems.append("ReviewView: grade buttons have no text label")

# 5. Reduce Motion honoured
if "accessibilityReduceMotion" not in read(os.path.join(VIEWS, "Components", "CommonViews.swift")):
    problems.append("ProgressRing does not honour Reduce Motion")
if "accessibilityReduceMotion" not in read(os.path.join(ROOT, "Services", "YouTubeEmbed.swift")):
    problems.append("GeneratedSceneView does not honour Reduce Motion")
if "accessibilityReduceMotion" not in read(os.path.join(VIEWS, "Review", "ReviewView.swift")):
    problems.append("Review card flip does not honour Reduce Motion")

if problems:
    print("FAILED")
    for problem in problems:
        print(" -", problem)
    sys.exit(1)

print(f"OK: no hardcoded font sizes; {button_total} buttons checked (glyph-only ones labelled); charts expose values; colour has a second channel; Reduce Motion honoured")
