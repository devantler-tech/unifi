#!/usr/bin/env bash
# Self-test for check-import-first.sh — proves the guard PASSES the empty,
# imported and marked configs and FAILS an un-imported resource. Run in CI so
# the guard's correctness is continuously verified (negative test per the AC).
set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guard="$here/check-import-first.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0

pass_case() { # name dir
  if "$guard" "$2" >/dev/null 2>&1; then
    printf '  ✅ %s — passed as expected\n' "$1"
  else
    printf '  ❌ %s — expected PASS but the guard FAILED\n' "$1"; fail=1
  fi
}

fail_case() { # name dir
  if "$guard" "$2" >/dev/null 2>&1; then
    printf '  ❌ %s — expected FAIL but the guard PASSED\n' "$1"; fail=1
  else
    printf '  ✅ %s — failed as expected\n' "$1"
  fi
}

# 1. empty / comment-only config → pass
mkdir -p "$tmp/empty"
cat > "$tmp/empty/main.tf" <<'EOF'
# Only comments here.
# resource "unifi_network" "iot" { }   # commented example, not a real resource
EOF
pass_case "empty/comment-only config" "$tmp/empty"

# 2. resource WITHOUT import or marker → fail
mkdir -p "$tmp/unguarded"
cat > "$tmp/unguarded/main.tf" <<'EOF'
resource "unifi_network" "iot" {
  name = "IoT"
}
EOF
fail_case "resource without import block" "$tmp/unguarded"

# 3. resource WITH matching import block → pass
mkdir -p "$tmp/imported"
cat > "$tmp/imported/main.tf" <<'EOF'
import {
  to = unifi_network.iot
  id = "abc123"
}
resource "unifi_network" "iot" {
  name = "IoT"
}
EOF
pass_case "resource with matching import block" "$tmp/imported"

# 4. genuinely-new resource WITH reviewed marker → pass
mkdir -p "$tmp/marked"
cat > "$tmp/marked/main.tf" <<'EOF'
# import-first:new brand-new guest VLAN, does not exist on the controller yet
resource "unifi_network" "guest" {
  name = "Guest"
}
EOF
pass_case "new resource with reviewed marker" "$tmp/marked"

# 5. one imported + one un-imported in the same dir → fail (catches the gap)
mkdir -p "$tmp/mixed"
cat > "$tmp/mixed/main.tf" <<'EOF'
import {
  to = unifi_network.iot
  id = "abc123"
}
resource "unifi_network" "iot" { name = "IoT" }
resource "unifi_wlan" "guest" { name = "guest-ssid" }
EOF
fail_case "mixed imported + un-imported resources" "$tmp/mixed"

# 6. marker must NOT leak to an unrelated later resource → fail
mkdir -p "$tmp/leak"
cat > "$tmp/leak/main.tf" <<'EOF'
# import-first:new the guest VLAN is new
resource "unifi_network" "guest" { name = "Guest" }

resource "unifi_network" "iot" { name = "IoT" }
EOF
fail_case "marker does not leak to a later resource" "$tmp/leak"

if [ "$fail" -ne 0 ]; then
  printf '❌ import-first guard self-test FAILED\n' >&2
  exit 1
fi
printf '✅ import-first guard self-test passed (6 cases)\n'
