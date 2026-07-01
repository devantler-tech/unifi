# unifi

Declarative configuration for my [UniFi](https://www.ui.com/) network, managed as
native Kubernetes resources with
[Crossplane](https://www.crossplane.io/) and the
[`provider-upjet-unifi`](https://github.com/devantler-tech/provider-upjet-unifi)
provider.

This repo is the **desired state** of the network (the WireGuard VPN client,
traffic routes, local DNS records, …), expressed as Crossplane **Managed
Resources** (`Client`, `TrafficRoute`, `Record`, …). It is reconciled
**continuously** on the [platform](https://github.com/devantler-tech/platform): a
Flux `Kustomization` pulls this repo as a `GitRepository` and applies the
resources into the `unifi` namespace, and `provider-upjet-unifi` (installed as a
Crossplane provider package) reconciles each one against the UniFi controller
API. There is no Terraform and no separate state store — the Managed Resource
*is* the state, with its observed status in `.status.atProvider`.

```
this repo (Crossplane MRs)
   │ Flux GitRepository + Kustomization  →  namespace: unifi
   ▼
provider-upjet-unifi (Crossplane, crossplane-system)  ──►  UniFi Controller API
```

## Golden rule: adopt-first

Never let the first reconcile create or destroy live network config. A Managed
Resource whose external object **already exists** must **adopt** it, not create a
duplicate. To bring an existing object under management:

1. Write the Managed Resource to match what already exists on the controller.
2. Add the annotation `crossplane.io/external-name: <unifi-id>` so Crossplane
   binds to the live object instead of creating a new one.
3. (Optional, safest) start it with `spec.managementPolicies: ["Observe"]` so the
   first reconcile only *reads* the object; confirm `.status.atProvider` matches,
   then widen to the default `["*"]` to manage it.

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

## Local use (validate / build)

```sh
kustomize build .                         # render the Managed Resources
kustomize build . | kubeconform -strict -ignore-missing-schemas -summary
```

CRD-schema validation against the provider's own CRDs (in
[`provider-upjet-unifi`](https://github.com/devantler-tech/provider-upjet-unifi)
under `package/crds/`) happens authoritatively server-side at apply time, and can
be run locally by pointing `kubeconform` at those schemas. CI (`.github/workflows/ci.yaml`)
runs `kustomize build` + `kubeconform` and aggregates them into the single
required `CI - Required Checks` status.

## Roadmap

This repo *is* the steady-state Crossplane model (it replaced an interim
OpenTofu + tofu-controller setup). Next steps are tracked in the
[monorepo](https://github.com/devantler-tech/monorepo) issues — e.g. a
cross-resource reference so a `TrafficRoute` can point at a `Client` by name
instead of a post-create network id, and bringing more of the network
(VLANs/WLANs/firewall) under management adopt-first.

## License

[Apache-2.0](LICENSE).
