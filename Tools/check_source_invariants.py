#!/usr/bin/env python3
"""Source-level invariants that a headless Linux host cannot exercise through SwiftUI.

Covers the two v0.8.0 real-device fixes and a few "no secrets / no stray tokens"
rules that must hold regardless of the build environment.
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Kotoba")
problems = []


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


settings = read(os.path.join(ROOT, "Views", "Settings", "SettingsView.swift"))
app_model = read(os.path.join(ROOT, "App", "AppModel.swift"))

# Fix 1: the picker shows the stored choice, not the normalised engine mode.
if "private var selectedMode" not in settings:
    problems.append("SettingsView: selectedMode is missing")
if not re.search(r"get:\s*\{\s*selectedMode\s*\}", settings):
    problems.append("SettingsView: Picker binding does not read selectedMode")
if not re.search(r"set:[^\n]*\$0\.mode\s*=\s*value", settings):
    problems.append("SettingsView: Picker setter no longer stores voiceOptions.mode")
if "selectedMode == .server" not in settings:
    problems.append("SettingsView: server address field is not gated on selectedMode")
if re.search(r"get:\s*\{\s*app\.voiceOptions\.effectiveMode", settings):
    problems.append("SettingsView: Picker still reads effectiveMode")

# Fix 2: one-time migration for pre-0.8.0 archives.
if "shouldMigrateServerAddress" not in app_model:
    problems.append("AppModel: migration helper missing")
if not re.search(r"if Self\.shouldMigrateServerAddress\(", app_model):
    problems.append("AppModel: migration helper is not called")
if "transcription.serverURL = ServerDefaults.baseURL" not in app_model:
    problems.append("AppModel: migration does not fill the default address")
if "didMigrateServerAddress = true" not in app_model:
    problems.append("AppModel: migration does not persist its result")
if "effectiveMode(transcriptionURL:" not in app_model:
    problems.append("AppModel: engine normalisation no longer uses effectiveMode")

# No secret material anywhere near the network clients.
for name in ("ServerTTSService.swift", "EdgeTTSService.swift", "TranscriptionClient.swift"):
    text = read(os.path.join(ROOT, "Services", name))
    if re.search(r"Authorization|Bearer\s|api[_-]?key\s*=", text, re.I):
        problems.append(f"{name}: looks like it embeds an auth header or key")

if problems:
    print("FAILED")
    for problem in problems:
        print(" -", problem)
    sys.exit(1)

print("OK: selectedMode drives the picker; migration helper wired into apply; no secrets in network clients")
