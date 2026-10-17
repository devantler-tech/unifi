# unifi

Declarative configuration for my [UniFi](https://www.ui.com/) network, managed as
native Kubernetes resources with
[Crossplane](https://www.crossplane.io/) and the
[`provider-upjet-unifi`](https://github.com/devantler-tech/provider-upjet-unifi)
provider.

This is one home network's desired-state configuration, not a general-purpose UniFi
tool. Start with a local render; changing the live network requires the separately
managed [platform](https://github.com/devantler-tech/platform) and authorized
controller access.

## Render locally

You need Git and `kubectl` with its built-in Kustomize command. No UniFi controller,
credentials or running cluster are needed for this check. From a directory where you
want a source checkout:

```sh
git clone https://github.com/devantler-tech/unifi.git
cd unifi
kubectl kustomize .
```

Success is a zero exit status and nine rendered resources: one `Client`, one
`TrafficRoute` and seven `Record`s, each carrying the annotation
`crossplane.io/paused: "true"`. The render builds the checked-in manifest set. It does
not apply anything, contact the controller or prove that the live network matches.

If you have [`kubeconform`](https://github.com/yannh/kubeconform) installed, you can
also run the structural check CI runs:

```sh
kubectl kustomize . | kubeconform -strict -ignore-missing-schemas -summary
```

Expect `Valid: 0, Invalid: 0, Errors: 0, Skipped: 9`. All nine resources are skipped
because their kinds are custom resources whose schemas `kubeconform` does not have, so
this check catches malformed YAML and nothing more.

CI also checks every field against the provider's own CRD schema, for the release the
Platform pins. To run that check locally, render the manifests to a file outside the
repository and pass it to the script. It needs network access, plus `kubeconform`, `yq` (v4)
and `jq`:

```sh
kubectl kustomize . > "${TMPDIR:-/tmp}/unifi-manifests.yaml"
bash scripts/validate-crd-schemas.sh "${TMPDIR:-/tmp}/unifi-manifests.yaml"
```

Expect `Valid: 9, Invalid: 0, Errors: 0, Skipped: 0`. A misspelled field, a wrong value type
or a missing required field makes the check fail.

## Current state: everything here is paused

Every resource in this repository is held with `crossplane.io/paused: "true"`, set
once in [`kustomization.yaml`](kustomization.yaml). While a resource is paused,
Crossplane does not create, change or delete anything on the controller for it.

The pause is deliberate. The resources still contain placeholders (the VPN peer
address, the VPN network id and the internal address the admin DNS records point at)
that can be filled in only once the platform's WireGuard server exists. Applying them
earlier would fail the VPN client and point the admin hostnames at an address that
does not answer. The comment in `kustomization.yaml` records when the pause may be
lifted. Removing the annotation is a reviewed change to the live network, never a
documentation or onboarding step.

## How it works

This repository is the **desired state** of the network (the WireGuard VPN client,
traffic routes, local DNS records, …), expressed as Crossplane **Managed Resources**
(`Client`, `TrafficRoute`, `Record`, …). There is no Terraform and no separate state
store: the Managed Resource *is* the state, with its observed status in
`.status.atProvider`.

```
this repo (Crossplane MRs)
   │ Flux GitRepository (one pinned, signed commit) + Kustomization  →  namespace: unifi
   ▼
provider-upjet-unifi (Crossplane, crossplane-system)  ──►  UniFi Controller API
```

The [platform](https://github.com/devantler-tech/platform) reads this repository at
**one commit it pins** and verifies that commit's signature before applying the
resources into the `unifi` namespace. There `provider-upjet-unifi` reconciles each
resource that is not paused against the UniFi controller API. A merge here therefore
changes nothing on the platform by itself: the pinned commit is moved in a separately
reviewed platform change.

## Golden rule: adopt-first

Never let the first reconcile create or destroy live network config. A Managed
Resource whose external object **already exists** must **adopt** it, not create a
duplicate. To bring an existing object under management:

1. Write the Managed Resource to match what already exists on the controller.
2. Add the annotation `crossplane.io/external-name: <unifi-id>` so Crossplane
   binds to the live object instead of creating a new one.
3. (Optional, safest) start it read-only: annotate it
   `platform.devantler.tech/unifi-management: observe-only` **and** set
   `spec.managementPolicies: ["Observe"]`, so the first reconcile only *reads* the
   object; confirm `.status.atProvider` matches, then remove both to manage it. The
   Platform honours the annotation and replaces any declared `managementPolicies`, so
   the annotation is what keeps it read-only.

For a genuinely **new** object the network does not have yet (like everything
shipped here today), no annotation is needed — Crossplane creates it. See the
[runbook](docs/runbook.md) for the step-by-step procedure and how to find a live
object's id.

## Authentication

API-key auth (UniFi Controller ≥ 9.0.108). Use a dedicated service account with a
**Limited Admin, Local Access Only** role. This repo is **public and holds no
secrets**: the controller credentials live in the platform's secret store
(OpenBao) and are surfaced to Crossplane as a `ProviderConfig` whose `secretRef`
points at a Secret produced by an External Secret — **never commit them here**.

| Credential | Meaning |
| --- | --- |
| `api_url` | Controller base URL, **without** the `/api` path |
| `api_key` | API key (sensitive) |
| `site` | Site to manage (default `default`) |
| `allow_insecure` | Skip TLS verify — only for a self-signed cert |

The WireGuard VPN client additionally references two keys from a Secret in the
`unifi` namespace (`cluster-wireguard`): the gateway's own **private key**
(sensitive) and the Talos server's **public key**. Both are seeded by the
platform; see the [runbook](docs/runbook.md#runbook-b--service-account--api-key-rotation).

## Contributing

Follow [CONTRIBUTING.md](CONTRIBUTING.md) for a safe first change, the local checks
and how to submit. The [CI workflow](.github/workflows/ci.yaml) renders the manifests,
runs the structural check above and scans the documentation for links to retired
repositories; passing it is not validation against the live network.

## Roadmap

This repo *is* the steady-state Crossplane model (it replaced an interim
OpenTofu + tofu-controller setup). Next steps are tracked in the
[monorepo](https://github.com/devantler-tech/monorepo) issues — e.g. a
cross-resource reference so a `TrafficRoute` can point at a `Client` by name
instead of a post-create network id, and bringing more of the network
(VLANs/WLANs/firewall) under management adopt-first.

## License

[Apache-2.0](LICENSE).
