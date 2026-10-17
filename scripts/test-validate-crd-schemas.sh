#!/usr/bin/env bash
#
# Self-test for validate-crd-schemas.sh. The rendered manifests must pass, and
# each seeded defect must fail. A check that passes on broken input is a defect,
# so every seeded case runs against its own copy of the manifests.
#
# The Platform's Provider manifest is read only by the validator, so
# PLATFORM_PROVIDER_MANIFEST points the self-test at a local copy too.
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
# The release the Platform runs, as the validator just read it. Scenarios 7–16 build on it, so the
# self-test never reads or parses the Platform's manifest a second time.
release="$(sed -n 's/^validate-crd-schemas: validating against devantler-tech\/provider-upjet-unifi \(v[0-9][0-9.]*\), the release the Platform runs$/\1/p' "${work}/last.log")"

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

# 7–16. The release comes from the Platform's Provider manifest. Each fixture is a small Provider
# document around the release scenario 1 read, so the fixtures follow the Platform's release, and
# the self-test keeps no second copy of its version or its URL.
[[ "${release}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || { echo "test-validate-crd-schemas: scenario 1 did not report the Platform's provider release (got '${release}')" >&2; exit 2; }
package="ghcr.io/devantler-tech/provider-upjet-unifi:${release}"
zero_digest="sha256:0000000000000000000000000000000000000000000000000000000000000000"

# provider writes a Provider manifest naming the given package to the given file.
provider() {
  printf 'apiVersion: pkg.crossplane.io/v1\nkind: Provider\nmetadata:\n  name: provider-upjet-unifi\nspec:\n  package: "%s"\n' "$2" > "$1"
}

# 7. A digest the tag does not resolve to is unknown: the CRDs at the tag are not what the Platform runs.
provider "${work}/provider-other-digest.yaml" "${package}@${zero_digest}"
expect_unknown "a digest the tag does not resolve to is unknown" "resolves to 'sha256:" "${work}/provider-other-digest.yaml"

# 8. The tag with the digest it resolves to passes. The digest is the one scenario 7 reported, so
# this proves the check accepts a matching digest, not merely that it rejects every digest.
own_digest="$(sed -n "s/.* resolves to '\(sha256:[0-9a-f]*\)'$/\1/p" "${work}/last.log")"
if [[ "${own_digest}" =~ ^sha256:[0123456789abcdef]{64}$ ]]; then
  provider "${work}/provider-own-digest.yaml" "${package}@${own_digest}"
  got="$(run_with_provider "${work}/provider-own-digest.yaml" "${manifests}")"
else
  got="no digest from scenario 7"
fi
if [ "${got}" = "0" ]; then
  echo "ok   a release tag with its own digest passes (exit 0)"
else
  echo "FAIL a release tag with its own digest: want exit 0, got ${got}" >&2
  cat "${work}/last.log" >&2
  failures=$((failures + 1))
fi

# 9–11. A digest that is not one well-formed sha256 is unknown before any registry call.
provider "${work}/provider-bad-digest.yaml" "${package}@sha256:not-a-digest"
expect_unknown "a malformed digest is unknown" "got '${package}@sha256:not-a-digest'" "${work}/provider-bad-digest.yaml"

upper_digest="sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
provider "${work}/provider-upper-digest.yaml" "${package}@${upper_digest}"
expect_unknown "an uppercase digest is unknown" "got '${package}@${upper_digest}'" "${work}/provider-upper-digest.yaml"

provider "${work}/provider-two-digests.yaml" "${package}@${zero_digest}@${zero_digest}"
expect_unknown "two digests are unknown" "got '${package}@${zero_digest}@${zero_digest}'" "${work}/provider-two-digests.yaml"

# 12–16. Every other shape is unknown too.
expect_unknown "unreadable Platform manifest is unknown" "could not read the Platform's Provider manifest" "${work}/provider-missing.yaml"

printf 'apiVersion: pkg.crossplane.io/v1\nkind: Provider\nmetadata:\n  name: provider-upjet-unifi\nspec: {}\n' > "${work}/provider-no-package.yaml"
expect_unknown "a Provider without a package is unknown" "got 'null'" "${work}/provider-no-package.yaml"

provider "${work}/provider-latest.yaml" "ghcr.io/devantler-tech/provider-upjet-unifi:latest"
expect_unknown "a non-release tag is unknown" "got 'ghcr.io/devantler-tech/provider-upjet-unifi:latest'" "${work}/provider-latest.yaml"

provider "${work}/provider-other.yaml" "ghcr.io/example/other-provider:v1.0.0"
expect_unknown "another package is unknown" "got 'ghcr.io/example/other-provider:v1.0.0'" "${work}/provider-other.yaml"

provider "${work}/provider-once.yaml" "${package}"
{ cat "${work}/provider-once.yaml"; printf -- '---\n'; cat "${work}/provider-once.yaml"; } > "${work}/provider-twice.yaml"
expect_unknown "two Provider documents are unknown" "is not ghcr.io/devantler-tech/provider-upjet-unifi" "${work}/provider-twice.yaml"

# 17. The validator uses the release the Provider manifest names, checked against a version this
# test states itself. Scenarios 7–16 build on the release scenario 1 reported, so on their own they
# would still pass if the validator picked the wrong release. v1.0.5 is a published, immutable tag
# whose CRDs accept the current manifests.
known_release="v1.0.5"
provider "${work}/provider-known.yaml" "ghcr.io/devantler-tech/provider-upjet-unifi:${known_release}"
got="$(run_with_provider "${work}/provider-known.yaml" "${manifests}")"
if [ "${got}" = "0" ] \
  && grep -qx "validate-crd-schemas: validating against devantler-tech/provider-upjet-unifi ${known_release}, the release the Platform runs" "${work}/last.log"; then
  echo "ok   the validator uses the release the Provider manifest names (exit 0, ${known_release})"
else
  echo "FAIL the validator must validate against ${known_release}, the release the Provider manifest names: got exit ${got}" >&2
  cat "${work}/last.log" >&2
  failures=$((failures + 1))
fi

if [ "${failures}" -gt 0 ]; then
  echo "test-validate-crd-schemas: ${failures} scenario(s) failed" >&2
  exit 1
fi
echo "test-validate-crd-schemas: all scenarios passed"
