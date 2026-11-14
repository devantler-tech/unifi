#!/usr/bin/env bash
#
# Self-test for validate-crossplane-schemas.sh. The rendered manifests must pass, and each
# seeded defect must fail. A check that passes on broken input is a defect, so every seeded case
# runs against its own copy of the manifests. The scenarios share one schema cache, so each
# package is downloaded once.
#
# Usage: CROSSPLANE_IMAGE=<image> test-validate-crossplane-schemas.sh <crossplane-binary> <rendered-manifests.yaml>

set -euo pipefail

crossplane="${1:?pass the crossplane CLI binary}"
manifests="${2:?pass the rendered manifests}"
validate="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/validate-crossplane-schemas.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
export CROSSPLANE_CACHE_DIR="${work}/cache"
failures=0

# run <provider-manifest-url|""> <manifests>: runs the validator, leaving its output in last.log
# and printing its exit status.
run() {
  local status=0
  if [ -n "$1" ]; then
    PLATFORM_PROVIDER_MANIFEST="$1" bash "${validate}" "${crossplane}" "$2" > "${work}/last.log" 2>&1 || status=$?
  else
    bash "${validate}" "${crossplane}" "$2" > "${work}/last.log" 2>&1 || status=$?
  fi
  echo "${status}"
}

# expect <name> <exit> <reason> <provider-manifest-url|""> <manifests>: asserts the exit status
# AND that the log names the reason, so a tool error with the same status never reads as a pass.
expect() {
  local got
  got="$(run "$4" "$5")"
  if [ "${got}" = "$2" ] && grep -qF -- "$3" "${work}/last.log"; then
    echo "ok   $1 (exit $2)"
  else
    echo "FAIL $1: want exit $2 and '$3', got exit ${got}" >&2
    cat "${work}/last.log" >&2
    failures=$((failures + 1))
  fi
}

# 1. The rendered manifests are valid, against the release the Platform runs.
expect "current manifests pass" 0 "0 failure cases" "" "${manifests}"
release="$(sed -n 's/^validate-crossplane-schemas: validating against ghcr.io\/devantler-tech\/provider-upjet-unifi \(v[0-9][0-9.]*\), the release the Platform runs$/\1/p' "${work}/last.log")"
[[ "${release}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || { echo "test-validate-crossplane-schemas: scenario 1 did not report the Platform's provider release (got '${release}')" >&2; exit 2; }

# 2–4. A misspelled field, a wrong value type and a missing required field fail.
yq e '(select(.kind == "Client") | .spec.forProvider.subnetx) = "10.0.0.1/32"' "${manifests}" > "${work}/typo.yaml"
expect "misspelled field fails" 1 'unknown field: "subnetx"' "" "${work}/typo.yaml"
yq e '(select(.kind == "Client") | .spec.forProvider.defaultRoute) = "false"' "${manifests}" > "${work}/type.yaml"
expect "wrong value type fails" 1 "spec.forProvider.defaultRoute in body must be of type boolean" "" "${work}/type.yaml"
yq e 'del(select(.metadata.name == "admin-hubble") | .spec.forProvider)' "${manifests}" > "${work}/required.yaml"
expect "missing required field fails" 1 "admin-hubble : spec.forProvider: Required value" "" "${work}/required.yaml"

# 5. A kind no schema covers fails, rather than being skipped.
cp "${manifests}" "${work}/unschemed.yaml"
printf -- '---\napiVersion: example.com/v1\nkind: Seeded\nmetadata:\n  name: seeded\n' >> "${work}/unschemed.yaml"
expect "kind without a schema fails" 1 "could not find CRD/XRD for: example.com/v1, Kind=Seeded" "" "${work}/unschemed.yaml"

# 6. A missing manifests file is a usage error.
expect "missing manifests file is a usage error" 2 "usage:" "" "${work}/does-not-exist.yaml"

# 7–13. The release comes from the Platform's Provider manifest. Each fixture is a small Provider
# document around the release scenario 1 read, so the self-test keeps no second copy of it.
package="ghcr.io/devantler-tech/provider-upjet-unifi:${release}"
zero_digest="sha256:0000000000000000000000000000000000000000000000000000000000000000"
provider() { # <file> <package>
  printf 'apiVersion: pkg.crossplane.io/v1\nkind: Provider\nmetadata:\n  name: provider-upjet-unifi\nspec:\n  package: "%s"\n' "$2" > "$1"
}

# 7. A digest the tag does not resolve to fails: Crossplane pulls the digest, not the tag.
provider "${work}/provider-other-digest.yaml" "${package}@${zero_digest}"
expect "a digest that is not the release's fails" 1 "${zero_digest}: MANIFEST_UNKNOWN" "file://${work}/provider-other-digest.yaml" "${manifests}"

expect "unreadable Platform manifest is unknown" 2 "could not read the Platform's Provider manifest" "file://${work}/provider-missing.yaml" "${manifests}"

printf 'apiVersion: pkg.crossplane.io/v1\nkind: Provider\nmetadata:\n  name: provider-upjet-unifi\nspec: {}\n' > "${work}/provider-no-package.yaml"
expect "a Provider without a package is unknown" 2 "got 'null'" "file://${work}/provider-no-package.yaml" "${manifests}"

provider "${work}/provider-latest.yaml" "ghcr.io/devantler-tech/provider-upjet-unifi:latest"
expect "a non-release tag is unknown" 2 "got 'ghcr.io/devantler-tech/provider-upjet-unifi:latest'" "file://${work}/provider-latest.yaml" "${manifests}"

provider "${work}/provider-other.yaml" "ghcr.io/example/other-provider:v1.0.0"
expect "another package is unknown" 2 "got 'ghcr.io/example/other-provider:v1.0.0'" "file://${work}/provider-other.yaml" "${manifests}"

provider "${work}/provider-bad-digest.yaml" "${package}@sha256:not-a-digest"
expect "a malformed digest is unknown" 2 "got '${package}@sha256:not-a-digest'" "file://${work}/provider-bad-digest.yaml" "${manifests}"

provider "${work}/provider-once.yaml" "${package}"
{ cat "${work}/provider-once.yaml"; printf -- '---\n'; cat "${work}/provider-once.yaml"; } > "${work}/provider-twice.yaml"
expect "two Provider documents are unknown" 2 "is not ghcr.io/devantler-tech/provider-upjet-unifi" "file://${work}/provider-twice.yaml" "${manifests}"

# 14. The validator uses the release the Provider manifest names, checked against a version this
# test states itself: the scenarios above build on the release scenario 1 reported, so on their
# own they would still pass if the validator picked the wrong release. v1.0.5 is a published,
# immutable tag. The manifests are empty, so the scenario never depends on today's fields.
provider "${work}/provider-known.yaml" "ghcr.io/devantler-tech/provider-upjet-unifi:v1.0.5"
: > "${work}/empty.yaml"
expect "the release the Provider manifest names is used" 0 \
  "validating against ghcr.io/devantler-tech/provider-upjet-unifi v1.0.5, the release the Platform runs" \
  "file://${work}/provider-known.yaml" "${work}/empty.yaml"

if [ "${failures}" -gt 0 ]; then
  echo "test-validate-crossplane-schemas: ${failures} scenario(s) failed" >&2
  exit 1
fi
echo "test-validate-crossplane-schemas: all scenarios passed"
