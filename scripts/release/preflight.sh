#!/usr/bin/env bash
set -euo pipefail

MODE=""
SIGN_ID=""
VERSION=""
ZIP_PATH=""
BUILT_APP=""

usage() {
  cat <<USAGE
Usage: preflight.sh --mode <build|release|notarize|appcast> --sign-id <identity> [options]

Options:
  --version <version>   Release version (required for release/notarize/appcast)
  --zip <path>          Zip path (required for notarize/appcast)
  --built-app <path>    Built app path to validate exists
USAGE
}

fail() {
  echo "preflight: $*" >&2
  exit 1
}

require_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || fail "Required tool not found: $tool"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --sign-id)
      SIGN_ID="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --zip)
      ZIP_PATH="${2:-}"
      shift 2
      ;;
    --built-app)
      BUILT_APP="${2:-}"
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

[[ -n "$MODE" ]] || fail "--mode is required"
[[ -n "$SIGN_ID" ]] || fail "--sign-id is required"

case "$MODE" in
  build|release|notarize|appcast) ;;
  *) fail "Invalid mode: $MODE" ;;
esac

require_tool xcodebuild
require_tool codesign
require_tool xcrun
require_tool ditto
require_tool security

# Validate certificate exists.
if ! security find-identity -v -p codesigning | grep -F "$SIGN_ID" >/dev/null 2>&1; then
  echo "Available signing identities:" >&2
  security find-identity -v -p codesigning >&2 || true
  fail "Signing identity not found: $SIGN_ID"
fi

if [[ "$MODE" == "release" || "$MODE" == "notarize" || "$MODE" == "appcast" ]]; then
  [[ -n "$VERSION" ]] || fail "--version is required for mode '$MODE'"
  [[ "$VERSION" != "dev" ]] || fail "VERSION cannot be 'dev' for mode '$MODE' (use VERSION=vX.Y.Z)"
fi

if [[ "$MODE" == "notarize" || "$MODE" == "appcast" ]]; then
  [[ -n "$ZIP_PATH" ]] || fail "--zip is required for mode '$MODE'"
  [[ -f "$ZIP_PATH" ]] || fail "Zip not found: $ZIP_PATH"
fi

if [[ -n "$BUILT_APP" ]]; then
  [[ -d "$BUILT_APP" ]] || fail "Built app not found: $BUILT_APP"
fi

echo "preflight: OK (mode=$MODE)"
