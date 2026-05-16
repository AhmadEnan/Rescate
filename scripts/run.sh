#!/usr/bin/env bash
# Launches the Rescate app with the Vulkan dart-defines baked in so you never
# need to remember them. Pass any extra `flutter run` arguments after `--`.
#
#   ./scripts/run.sh                  # debug, attached
#   ./scripts/run.sh -- --release     # release build
#   ./scripts/run.sh -- -d <deviceId> # pick a specific device
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/apps/rescate_app"
cd "$APP"
exec flutter run \
  --dart-define-from-file="$APP/dart_defines.json" \
  "$@"
