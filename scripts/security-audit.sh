#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"

fail() {
  print -u2 "SECURITY AUDIT FAILED: $1"
  exit 1
}

# 1. No shell invocation in Swift sources.
if grep -rnE '"/bin/(sh|bash|zsh)"' Sources/ >/dev/null 2>&1; then
  grep -rnE '"/bin/(sh|bash|zsh)"' Sources/ >&2
  fail "Shell binary invocation found in Sources/"
fi

# 2. No Finder AppleScript or AppleEvents automation dependency.
if grep -rnE 'NSAppleScript|NSAppleEventsUsageDescription' Sources/ Support/ >/dev/null 2>&1; then
  grep -rnE 'NSAppleScript|NSAppleEventsUsageDescription' Sources/ Support/ >&2
  fail "AppleScript or AppleEvents usage found in Sources/ or Support/"
fi

# 3. No forbidden entitlements in Support/Explorer.entitlements.
FORBIDDEN=(
  com.apple.security.automation.apple-events
  com.apple.security.get-task-allow
  com.apple.security.cs.disable-library-validation
  com.apple.security.cs.allow-unsigned-executable-memory
  com.apple.security.cs.allow-dyld-environment-variables
)
for key in "${FORBIDDEN[@]}"; do
  if grep -q "$key" Support/Explorer.entitlements; then
    fail "Forbidden entitlement '$key' in Support/Explorer.entitlements"
  fi
done

# 4. Run full Swift test suite (XCTest + Swift Testing).
zsh scripts/test.sh

# 5. If a built bundle is present, verify signature and entitlements.
if [[ -d build/Explorer.app ]]; then
  codesign --verify --deep --strict build/Explorer.app
  ENTITLEMENTS=$(codesign -d --entitlements - build/Explorer.app 2>&1 || true)
  for key in "${FORBIDDEN[@]}"; do
    if print -r -- "$ENTITLEMENTS" | grep -q "$key"; then
      fail "Forbidden entitlement '$key' present in build/Explorer.app"
    fi
  done
fi

print "SECURITY AUDIT PASSED"
