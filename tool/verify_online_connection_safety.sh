#!/usr/bin/env bash
set -euo pipefail

# Run from any directory. This is the stop-the-line gate for edits that touch
# Quick Pop/Quick Table connection code; it never deploys rules or sends a
# build anywhere.
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

echo "[1/4] Formatting guard"
dart format --output=none --set-exit-if-changed \
  lib/online_connection_safety.dart \
  lib/firebase_online_transport.dart \
  test/online_connection_safety_test.dart

echo "[2/4] Static analysis"
flutter analyze --no-pub

echo "[3/4] Focused online regression tests"
flutter test --no-pub --reporter compact \
  test/online_connection_safety_test.dart \
  test/quick_pop_group_test.dart \
  test/online_transport_test.dart \
  test/quick_pop_online_diagnostics_test.dart

echo "[4/4] Whitespace and conflict guard"
git diff --check

if [[ "${RUN_PRODUCTION_SMOKE:-0}" == "1" ]]; then
  echo "[optional] Two-client Firebase smoke"
  flutter test --no-pub --reporter compact \
    test/quick_pop_production_smoke_test.dart
  echo "[optional] Four-client Firebase smoke"
  flutter test --no-pub --reporter compact \
    test/quick_pop_production_four_smoke_test.dart
fi

echo "ONLINE CONNECTION SAFETY: PASS"
