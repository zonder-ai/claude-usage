#!/usr/bin/env bash
set -euo pipefail

ZIP_PATH=""
EXPECT_STATE=""

usage() {
  cat <<USAGE
Usage: verify-artifact.sh --zip <release.zip> --expect <pre-notary|notarized>
USAGE
}

fail() {
  echo "verify-artifact: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zip)
      ZIP_PATH="${2:-}"
      shift 2
      ;;
    --expect)
      EXPECT_STATE="${2:-}"
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

[[ -n "$ZIP_PATH" ]] || fail "--zip is required"
[[ -f "$ZIP_PATH" ]] || fail "Zip not found: $ZIP_PATH"
[[ "$EXPECT_STATE" == "pre-notary" || "$EXPECT_STATE" == "notarized" ]] || fail "--expect must be pre-notary or notarized"

tmpdir=$(mktemp -d /tmp/aiusage-verify.XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT

# shellcheck disable=SC2034
extract_output=$(ditto -x -k "$ZIP_PATH" "$tmpdir" 2>&1) || fail "Failed to unzip artifact"

APP_PATH=$(find "$tmpdir" -maxdepth 3 -type d -name "*.app" | head -1)
[[ -n "$APP_PATH" ]] || fail "No .app bundle found in zip"

codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null 2>&1 || fail "codesign verify failed for $APP_PATH"

if find "$APP_PATH" -name '._*' -print -quit | grep -q .; then
  fail "Found AppleDouble files (._*) in app bundle"
fi

set +e
spctl_output=$(spctl --assess --type execute --verbose=4 "$APP_PATH" 2>&1)
spctl_rc=$?
set -e

if [[ "$EXPECT_STATE" == "notarized" ]]; then
  if [[ $spctl_rc -ne 0 ]]; then
    printf '%s\n' "$spctl_output" >&2
    fail "Expected notarized artifact, but spctl assessment failed"
  fi
else
  if [[ $spctl_rc -eq 0 ]]; then
    fail "Expected pre-notary artifact, but spctl passed (already notarized?)"
  fi
  if ! printf '%s\n' "$spctl_output" | grep -q "Unnotarized Developer ID"; then
    printf '%s\n' "$spctl_output" >&2
    fail "Expected pre-notary rejection 'Unnotarized Developer ID'"
  fi
fi

echo "verify-artifact: OK ($EXPECT_STATE)"
