#!/usr/bin/env bash
# Compile and run the app's decision layer on Linux (no Xcode required).
#
#   ./Tools/verify_logic.sh            # behaviour checks
#   swiftc ... (see below)             # typecheck only: add TYPE_CHECK_ONLY=1
#
# Platform frameworks (SwiftUI, AVFoundation, Security) are replaced by the
# stand-ins in Tools/stubs. This checks logic, not UI rendering.
set -euo pipefail
cd "$(dirname "$0")/.."

SWIFTC="${SWIFTC:-swiftc}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FILES=(
  Kotoba/Model/LanguageModels.swift
  Kotoba/Model/Clip.swift
  Kotoba/Model/Scheduling.swift
  Kotoba/Model/VocabularyModels.swift
  Kotoba/Model/ProfileModels.swift
  Kotoba/Services/Deinflector.swift
  Kotoba/Services/DictionaryStore.swift
  Kotoba/Services/Tokenizer.swift
  Kotoba/Services/FeedRanker.swift
  Kotoba/Services/ContextExplainer.swift
  Kotoba/Services/ClipLibrary.swift
  Kotoba/Services/ReviewSession.swift
  Kotoba/Services/SubtitleImport.swift
  Kotoba/Services/BackupService.swift
  Kotoba/App/AppModel.swift
  Tools/stubs/PlatformShim.swift
)

for file in "${FILES[@]}"; do
  # SwiftUI is only used for ObservableObject/withAnimation in these files.
  sed '/^import SwiftUI$/d' "$file" > "$WORK/$(echo "$file" | tr '/' '_')"
done

if [ "${TYPE_CHECK_ONLY:-0}" = "1" ]; then
  "$SWIFTC" -typecheck -swift-version 5 "$WORK"/*.swift
  echo "typecheck OK (${#FILES[@]} logic files)"
  exit 0
fi

cp Tools/HarnessLogic.swift "$WORK/$(basename Tools/HarnessLogic.swift)"
"$SWIFTC" -swift-version 5 -Onone "$WORK"/*.swift -o "$WORK/harness"
"$WORK/harness" Kotoba/Resources/Dictionary.json
