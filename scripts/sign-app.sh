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
