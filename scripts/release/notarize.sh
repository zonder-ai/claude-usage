#!/usr/bin/env bash
set -euo pipefail

ZIP_PATH=""
APP_PATH=""
DEFAULT_TEAM_ID="X77R7CFNAY"
TEAM_ID="$DEFAULT_TEAM_ID"

usage() {
  cat <<USAGE
Usage: notarize.sh --zip <release.zip> [--app <path-to-app>] [--team <team-id>]

Auth mode 1 (recommended):
  APPLE_ID, APPLE_APP_PASSWORD, optional APPLE_TEAM_ID

Auth mode 2 (fallback):
  NOTARY_KEYCHAIN_PROFILE
USAGE
}

fail() {
  echo "notarize: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zip)
      ZIP_PATH="${2:-}"
      shift 2
      ;;
    --app)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --team)
      TEAM_ID="${2:-}"
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

AUTH_ARGS=()
AUTH_MODE=""

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  AUTH_MODE="apple-id"
  AUTH_ARGS=(--apple-id "$APPLE_ID" --team-id "${APPLE_TEAM_ID:-$TEAM_ID}" --password "$APPLE_APP_PASSWORD")
elif [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  AUTH_MODE="keychain-profile"
  AUTH_ARGS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
else
  fail "No notary credentials configured. Set APPLE_ID + APPLE_APP_PASSWORD (and optional APPLE_TEAM_ID) or NOTARY_KEYCHAIN_PROFILE."
fi

tmpdir=""
cleanup() {
  if [[ -n "$tmpdir" && -d "$tmpdir" ]]; then
    rm -rf "$tmpdir"
  fi
}
trap cleanup EXIT

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  tmpdir=$(mktemp -d /tmp/aiusage-notarize.XXXXXX)
  ditto -x -k "$ZIP_PATH" "$tmpdir"
  APP_PATH=$(find "$tmpdir" -maxdepth 3 -type d -name "*.app" | head -1)
  [[ -n "$APP_PATH" ]] || fail "Unable to locate .app bundle in zip"
fi

echo "notarize: submitting ($AUTH_MODE)"

submit_output=""
for attempt in 1 2 3; do
  set +e
  submit_output=$(xcrun notarytool submit "$ZIP_PATH" "${AUTH_ARGS[@]}" --output-format json 2>&1)
  submit_rc=$?
  set -e

  if [[ $submit_rc -eq 0 ]]; then
    break
  fi

  if printf '%s\n' "$submit_output" | grep -E "HTTP (Error )?429|status code: 429" >/dev/null 2>&1; then
    if [[ $attempt -lt 3 ]]; then
      delay=$((attempt * 30))
      echo "notarize: Apple rate-limited request (429), retrying in ${delay}s..."
      sleep "$delay"
      continue
    fi
  fi

  printf '%s\n' "$submit_output" >&2
  fail "notarytool submit failed"
done

submission_id=$(python3 -c 'import json,sys
raw=sys.stdin.read().strip()
try:
    j=json.loads(raw)
except Exception:
    print("")
    sys.exit(0)
print(j.get("id", ""))' <<<"$submit_output")

[[ -n "$submission_id" ]] || fail "Failed to parse submission id from notarytool output"

echo "notarize: waiting for submission $submission_id"

set +e
wait_output=$(xcrun notarytool wait "$submission_id" "${AUTH_ARGS[@]}" --output-format json 2>&1)
wait_rc=$?
set -e

wait_status=$(python3 -c 'import json,sys
raw=sys.stdin.read().strip()
try:
    j=json.loads(raw)
except Exception:
    print("")
    sys.exit(0)
print(j.get("status", ""))' <<<"$wait_output")

if [[ $wait_rc -ne 0 || "$wait_status" != "Accepted" ]]; then
  echo "notarize: submission did not succeed (status=${wait_status:-unknown}); fetching notary log..." >&2
  xcrun notarytool log "$submission_id" "${AUTH_ARGS[@]}" --output-format json >&2 || true
  [[ -n "$wait_output" ]] && printf '%s\n' "$wait_output" >&2
  fail "Notarization failed"
fi

echo "notarize: accepted, stapling"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# Recreate zip from stapled app bundle.
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Gatekeeper assessment is intentionally handled by verify-artifact.sh.
# For notarized app bundles under temp/DerivedData paths, spctl may emit
# non-actionable "does not seem to be an app" / internal assessment errors.
# Stapler validation is the deterministic gate for this script.

echo "notarize: OK"
