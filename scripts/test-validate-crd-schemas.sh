#!/usr/bin/env bash
#
# Self-test for validate-crd-schemas.sh. The rendered manifests must pass, and
# each seeded defect must fail. A check that passes on broken input is a defect,
# so every seeded case runs against its own copy of the manifests.
#
# Usage: test-validate-crd-schemas.sh <rendered-manifests.yaml>

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
validate="${here}/validate-crd-schemas.sh"
manifests="${1:-}"
if [ -z "${manifests}" ] || [ ! -f "${manifests}" ]; then
  echo "usage: test-validate-crd-schemas.sh <rendered-manifests.yaml>" >&2
  exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failures=0

# run executes the validator on one manifests file, leaving its output in last.log.
run() {
  local status=0
  bash "${validate}" "$1" >"${work}/last.log" 2>&1 || status=$?
  printf '%s' "${status}"
}

# run_with_provider is run with the Platform's Provider manifest read from a local file.
run_with_provider() {
  local status=0
  PLATFORM_PROVIDER_MANIFEST="file://$1" bash "${validate}" "$2" >"${work}/last.log" 2>&1 || status=$?
  printf '%s' "${status}"
}

# expect_unknown asserts exit 2 AND the log names the reason, with the Platform's
# Provider manifest read from the given file. An unknown version must never pass.
expect_unknown() {
  local name="$1" pattern="$2" provider="$3" got
  got="$(run_with_provider "${provider}" "${manifests}")"
  if [ "${got}" = "2" ] && grep -q -- "${pattern}" "${work}/last.log"; then
    echo "ok   ${name} (exit 2, reason: ${pattern})"
  else
    echo "FAIL ${name}: want exit 2 naming '${pattern}', got exit ${got}" >&2
    cat "${work}/last.log" >&2
    failures=$((failures + 1))
  fi
}

# expect_pass asserts exit 0.
expect_pass() {
  local name="$1" file="$2" got
  got="$(run "${file}")"
  if [ "${got}" = "0" ]; then
    echo "ok   ${name} (exit 0)"
  else
    echo "FAIL ${name}: want exit 0, got ${got}" >&2
    cat "${work}/last.log" >&2
    failures=$((failures + 1))
  fi
}

# expect_reject asserts exit 1 AND the log names the seeded defect. A tool error
# that happens to exit 1 must not read as a rejection, so the reason is required.
expect_reject() {
  local name="$1" pattern="$2" file="$3" got
  got="$(run "${file}")"
  if [ "${got}" = "1" ] && grep -q -- "${pattern}" "${work}/last.log"; then
    echo "ok   ${name} (exit 1, reason: ${pattern})"
  else
    echo "FAIL ${name}: want exit 1 naming '${pattern}', got exit ${got}" >&2
    cat "${work}/last.log" >&2
    failures=$((failures + 1))
  fi
}

# 1. The rendered manifests are valid.
expect_pass "current manifests pass" "${manifests}"

# 2. A misspelled field in a Client fails: the closed schema rejects unknown fields.
yq e '(select(.kind == "Client") | .spec.forProvider.subnetx) = "10.0.0.1/32"' "${manifests}" > "${work}/typo.yaml"
expect_reject "misspelled field fails" "additional properties 'subnetx' not allowed" "${work}/typo.yaml"

# 3. A wrong value type fails.
yq e '(select(.kind == "Client") | .spec.forProvider.defaultRoute) = "false"' "${manifests}" > "${work}/type.yaml"
expect_reject "wrong value type fails" "got string, want boolean" "${work}/type.yaml"

# 4. A missing required field fails.
yq e 'del(select(.metadata.name == "admin-hubble") | .spec.forProvider)' "${manifests}" > "${work}/required.yaml"
expect_reject "missing required field fails" "missing property 'forProvider'" "${work}/required.yaml"

# 5. A kind with no pinned schema fails, rather than being skipped.
cp "${manifests}" "${work}/unpinned.yaml"
printf -- '---\napiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: seeded-unpinned\ndata:\n  key: value\n' >> "${work}/unpinned.yaml"
expect_reject "kind without a pinned schema fails" "ConfigMap" "${work}/unpinned.yaml"

# 6. A missing manifests argument is a usage error (2), never a pass.
status=0
bash "${validate}" "${work}/does-not-exist.yaml" >/dev/null 2>&1 || status=$?
if [ "${status}" = "2" ]; then
  echo "ok   missing manifests file is a usage error (exit 2)"
else
  echo "FAIL missing manifests file: want exit 2, got ${status}" >&2
  failures=$((failures + 1))
fi

# 7–11. The version comes from the Platform's Provider manifest. Fixtures are built from the
# manifest the Platform pins today, so they follow its release instead of a second copy here.
live="${work}/provider-live.yaml"
curl -fsSL "https://raw.githubusercontent.com/devantler-tech/platform/main/k8s/providers/hetzner/infrastructure/crossplane/provider-upjet-unifi.yaml" -o "${live}" \
  || { echo "test-validate-crd-schemas: could not read the Platform's Provider manifest" >&2; exit 2; }
package="$(yq e 'select(.kind == "Provider") | .spec.package' "${live}")"
zero_digest="0000000000000000000000000000000000000000000000000000000000000000"

yq e "(select(.kind == \"Provider\") | .spec.package) = \"${package}@sha256:${zero_digest}\"" "${live}" > "${work}/provider-digest.yaml"
got="$(run_with_provider "${work}/provider-digest.yaml" "${manifests}")"
if [ "${got}" = "0" ]; then
  echo "ok   a release tag followed by a digest passes (exit 0)"
else
  echo "FAIL a release tag followed by a digest: want exit 0, got ${got}" >&2
  cat "${work}/last.log" >&2
  failures=$((failures + 1))
fi

expect_unknown "unreadable Platform manifest is unknown" "could not read the Platform's Provider manifest" "${work}/provider-missing.yaml"

yq e '(select(.kind == "Provider") | .spec.package) = "ghcr.io/devantler-tech/provider-upjet-unifi:latest"' "${live}" > "${work}/provider-latest.yaml"
expect_unknown "a non-release tag is unknown" "got 'ghcr.io/devantler-tech/provider-upjet-unifi:latest'" "${work}/provider-latest.yaml"

yq e '(select(.kind == "Provider") | .spec.package) = "ghcr.io/example/other-provider:v1.0.0"' "${live}" > "${work}/provider-other.yaml"
expect_unknown "another package is unknown" "got 'ghcr.io/example/other-provider:v1.0.0'" "${work}/provider-other.yaml"

{ cat "${live}"; printf -- '\n---\n'; cat "${live}"; } > "${work}/provider-twice.yaml"
expect_unknown "two Provider documents are unknown" "is not ghcr.io/devantler-tech/provider-upjet-unifi" "${work}/provider-twice.yaml"

if [ "${failures}" -gt 0 ]; then
  echo "test-validate-crd-schemas: ${failures} scenario(s) failed" >&2
  exit 1
fi
echo "test-validate-crd-schemas: all scenarios passed"
