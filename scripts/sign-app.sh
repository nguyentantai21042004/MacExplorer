#!/bin/zsh
set -euo pipefail
APP_PATH="${1:?App bundle required}"
SIGNING_IDENTITY="${2:--}"
SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != '-' ]]; then
  [[ "$SIGNING_IDENTITY" == 'Developer ID Application:'* ]] || { print -u2 'A Developer ID Application identity is required'; exit 1; }
  SIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_ARGS[@]}" --entitlements "${0:A:h:h}/Support/Explorer.entitlements" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

ENTITLEMENTS=$(codesign -d --entitlements - "$APP_PATH" 2>&1 || true)
FORBIDDEN_ENTITLEMENTS=(
  com.apple.security.automation.apple-events
  com.apple.security.get-task-allow
  com.apple.security.cs.disable-library-validation
  com.apple.security.cs.allow-unsigned-executable-memory
  com.apple.security.cs.allow-dyld-environment-variables
)
for key in "${FORBIDDEN_ENTITLEMENTS[@]}"; do
  if print -r -- "$ENTITLEMENTS" | grep -q "$key"; then
    print -u2 "Security gate failed: forbidden entitlement '$key' present in $APP_PATH"
    exit 1
  fi
done

if [[ "$SIGNING_IDENTITY" != '-' ]]; then
  SIGN_INFO=$(codesign -dvv "$APP_PATH" 2>&1)
  if ! print -r -- "$SIGN_INFO" | grep -q 'flags=.*runtime'; then
    print -u2 "Security gate failed: Hardened Runtime flag missing on release bundle $APP_PATH"
    exit 1
  fi
fi
