#!/usr/bin/env bash
set -euo pipefail

APP_PATH=""
EXPECTED_TEAM=""

usage() {
  cat <<USAGE
Usage: check-sparkle-signatures.sh --app <path-to-app> --team <team-id>
USAGE
}

fail() {
  echo "sparkle-signatures: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --team)
      EXPECTED_TEAM="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$APP_PATH" ]] || fail "--app is required"
[[ -n "$EXPECTED_TEAM" ]] || fail "--team is required"
[[ -d "$APP_PATH" ]] || fail "App not found: $APP_PATH"

SPARKLE_ROOT="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
TARGETS=(
  "$SPARKLE_ROOT/Sparkle"
  "$SPARKLE_ROOT/Autoupdate"
  "$SPARKLE_ROOT/Updater.app/Contents/MacOS/Updater"
  "$SPARKLE_ROOT/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
  "$SPARKLE_ROOT/XPCServices/Installer.xpc/Contents/MacOS/Installer"
)

for bin in "${TARGETS[@]}"; do
  [[ -f "$bin" ]] || fail "Missing Sparkle binary: $bin"

  codesign --verify --strict --verbose=2 "$bin" >/dev/null 2>&1 || fail "codesign verify failed: $bin"

  info=$(codesign -dv "$bin" 2>&1)
  team=$(printf '%s\n' "$info" | sed -n 's/^TeamIdentifier=//p' | head -1)
  timestamp=$(printf '%s\n' "$info" | sed -n 's/^Timestamp=//p' | head -1)

  [[ -n "$team" ]] || fail "Missing TeamIdentifier in signature: $bin"
  [[ "$team" == "$EXPECTED_TEAM" ]] || fail "TeamIdentifier mismatch for $bin (expected $EXPECTED_TEAM, got $team)"
  [[ -n "$timestamp" ]] || fail "Missing secure timestamp in signature: $bin"

  echo "sparkle-signatures: OK $(basename "$bin")"
done

echo "sparkle-signatures: all Sparkle binaries are valid"
