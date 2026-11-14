#!/usr/bin/env bash
#
# Validates the rendered manifests with `crossplane resource validate`, against the provider
# package the Platform runs. Every field is checked against the provider's own schema, an
# unknown field is an error, and a kind no schema covers fails instead of being skipped.
#
# The provider version has one source: the Platform's Provider manifest, read from the
# Platform's main branch and passed to Crossplane as the package to validate against. When that
# package also pins a digest, Crossplane pulls the digest, so the schemas are the ones the
# Platform runs.
#
# PLATFORM_PROVIDER_MANIFEST overrides where the Provider manifest is read from (any URL curl
# accepts, including file://); the self-test uses it. CROSSPLANE_CACHE_DIR reuses downloaded
# schemas between runs.
#
# Usage: CROSSPLANE_IMAGE=<image> validate-crossplane-schemas.sh <crossplane-binary> <rendered-manifests.yaml>
# Exit: 0 every resource is valid, 1 a resource is invalid or has no schema, 2 usage error, or
#       the Platform's Provider manifest is unreadable or does not name one release.

set -euo pipefail

PACKAGE="ghcr.io/devantler-tech/provider-upjet-unifi"
PLATFORM_PROVIDER_MANIFEST="${PLATFORM_PROVIDER_MANIFEST:-https://raw.githubusercontent.com/devantler-tech/platform/main/k8s/providers/hetzner/infrastructure/crossplane/provider-upjet-unifi.yaml}"

crossplane="${1:-}"
manifests="${2:-}"
if [ -z "${crossplane}" ] || [ -z "${manifests}" ] || [ ! -f "${manifests}" ] || [ -z "${CROSSPLANE_IMAGE:-}" ]; then
  echo "usage: CROSSPLANE_IMAGE=<image> validate-crossplane-schemas.sh <crossplane-binary> <rendered-manifests.yaml>" >&2
  exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

curl -fsSL "${PLATFORM_PROVIDER_MANIFEST}" -o "${work}/platform.yaml" \
  || { echo "validate-crossplane-schemas: could not read the Platform's Provider manifest at ${PLATFORM_PROVIDER_MANIFEST}" >&2; exit 2; }
yq e 'select(.kind == "Provider" and .metadata.name == "provider-upjet-unifi")' "${work}/platform.yaml" > "${work}/provider.yaml" \
  || { echo "validate-crossplane-schemas: the Platform's Provider manifest does not parse" >&2; exit 2; }
package="$(yq e '.spec.package' "${work}/provider.yaml")"
# Only one Provider document naming one release tag, with at most one lowercase sha256 digest, is
# accepted. Anything else (no package, another package or tag, two documents) is unknown, never a
# pass against a guessed version.
if ! [[ "${package}" =~ ^"${PACKAGE}:"(v[0-9]+\.[0-9]+\.[0-9]+)(@sha256:[0123456789abcdef]{64})?$ ]]; then
  echo "validate-crossplane-schemas: the Platform's Provider package is not ${PACKAGE}:v<major>.<minor>.<patch>, optionally followed by one @sha256:<64 lowercase hex> digest (got '${package}')" >&2
  exit 2
fi
echo "validate-crossplane-schemas: validating against ${PACKAGE} ${BASH_REMATCH[1]}, the release the Platform runs"

status=0
"${crossplane}" resource validate "${work}/provider.yaml" "${manifests}" \
  --error-on-missing-schemas \
  --crossplane-image "${CROSSPLANE_IMAGE}" \
  --cache-dir "${CROSSPLANE_CACHE_DIR:-${work}/cache}" || status=$?
[ "${status}" -eq 0 ] || exit 1
