#!/usr/bin/env bash
#
# Validates the rendered managed resources field by field against the schema of
# the provider release the Platform pins. kubeconform skips every UniFi kind
# (the catalogue has no schema for them), so without this step CI checks only
# that the YAML is well formed. A misspelled field would then reach the Platform
# and could be pruned on apply without an error.
#
# The schemas are the provider's own CRDs at PROVIDER_REF, fetched at that tag
# and never vendored. Their object schemas are closed (no unknown fields), so a
# field the CRD does not define is an error.
#
# Keep PROVIDER_REF equal to the version the Platform's Provider package pins,
# and change both in the same review (see AGENTS.md).
#
# Usage: validate-crd-schemas.sh <rendered-manifests.yaml>
# Exit: 0 every resource is valid, 1 a resource is invalid or has no pinned
#       schema, 2 usage error or a required tool or CRD is unavailable.

set -euo pipefail

PROVIDER_REPO="devantler-tech/provider-upjet-unifi"
PROVIDER_REF="v1.0.4"
# The CRDs in the provider's package/crds directory for each kind this repository manages.
CRDS=(
  "vpn.unifi.m.crossplane.io_clients.yaml"
  "route.unifi.m.crossplane.io_trafficroutes.yaml"
  "dns.unifi.m.crossplane.io_records.yaml"
)

manifests="${1:-}"
if [ -z "${manifests}" ] || [ ! -f "${manifests}" ]; then
  echo "usage: validate-crd-schemas.sh <rendered-manifests.yaml>" >&2
  exit 2
fi

for tool in curl jq kubeconform yq; do
  command -v "${tool}" >/dev/null 2>&1 || { echo "validate-crd-schemas: ${tool} is required" >&2; exit 2; }
done
yq --version 2>&1 | grep -q 'version v4' || { echo "validate-crd-schemas: yq v4 (mikefarah) is required" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
schemas="${work}/schemas"
base="https://raw.githubusercontent.com/${PROVIDER_REPO}/${PROVIDER_REF}/package/crds"

for crd in "${CRDS[@]}"; do
  curl -fsSL "${base}/${crd}" -o "${work}/${crd}" \
    || { echo "validate-crd-schemas: could not fetch ${crd} at ${PROVIDER_REF}" >&2; exit 2; }

  group="$(yq e '.spec.group' "${work}/${crd}")"
  kind="$(yq e '.spec.names.kind' "${work}/${crd}")"
  mkdir -p "${schemas}/${group}"

  # kubeconform looks up <group>/<kind>_<version>.json, with the kind lowercased, for each
  # served version. The lookup is case-sensitive on Linux runners but not on macOS, so the
  # file name must be lowercase to pass on both.
  kind_lower="$(printf '%s' "${kind}" | tr '[:upper:]' '[:lower:]')"
  served=0
  while IFS= read -r version; do
    out="${schemas}/${group}/${kind_lower}_${version}.json"
    yq -o=json ".spec.versions[] | select(.name == \"${version}\") | .schema.openAPIV3Schema" "${work}/${crd}" \
      | jq 'walk(if type == "object" and has("properties") and (has("additionalProperties") | not) and (.["x-kubernetes-preserve-unknown-fields"] != true) then . + {additionalProperties: false} else . end)' \
      > "${out}"
    jq -e 'type == "object"' "${out}" >/dev/null \
      || { echo "validate-crd-schemas: ${crd} has no schema for ${version}" >&2; exit 2; }
    served=$((served + 1))
  done < <(yq e '.spec.versions[] | select(.served == true) | .name' "${work}/${crd}")

  [ "${served}" -gt 0 ] || { echo "validate-crd-schemas: ${crd} serves no version" >&2; exit 2; }
done

# A kind without a pinned schema is an error here, not a skip: no
# -ignore-missing-schemas. Add the kind's CRD to CRDS when a new kind is managed.
kubeconform -strict -summary \
  -schema-location "${schemas}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
  "${manifests}"
