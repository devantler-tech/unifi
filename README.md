# unifi

Declarative configuration for my [UniFi](https://www.ui.com/) network, managed as
code with [OpenTofu](https://opentofu.org/)/Terraform and the
[`filipowm/unifi`](https://github.com/filipowm/terraform-provider-unifi) provider.

This repo is the **desired state** of the network (networks/VLANs, WLANs, firewall
rules, port forwards, DNS records, …). It is reconciled **continuously** by
[tofu-controller](https://flux-iac.github.io/tofu-controller/) on the
[platform](https://github.com/devantler-tech/platform): a `Terraform` custom
resource pulls this repo as a Flux `GitRepository`, runs `tofu plan`/`apply`
against the controller API, and keeps state in a Kubernetes Secret. There is no
`backend` block and no committed state — the cluster owns state.

```
this repo (OpenTofu, filipowm/unifi)
   │ Flux GitRepository
   ▼
Terraform CR (tofu-controller, namespace: unifi)  ──►  UniFi Controller API
```

## Golden rule: import-first

Never let a first apply create or destroy live network config. To bring an
existing object under management:

1. Write the `resource` to match what already exists.
2. Import it — e.g. `tofu import unifi_network.lan <id>` (or an `import {}` block).
3. Run `tofu plan` and confirm **no changes**.
4. Only then edit attributes to change the network.

An empty configuration (as shipped) plans to "No changes" — a safe no-op.

## Authentication

API-key auth (UniFi Controller ≥ 9.0.108). Use a dedicated service account with a
**Limited Admin, Local Access Only** role. The key is supplied to the reconciler by
the platform from `variables-cluster` (SOPS-encrypted) — **never commit it here**.

| Variable | Meaning |
| --- | --- |
| `unifi_api_url` | Controller base URL, **without** the `/api` path |
| `unifi_api_key` | API key (sensitive) |
| `unifi_site` | Site to manage (default `default`) |
| `unifi_allow_insecure` | Skip TLS verify — only for a self-signed cert |

## Local use (read-only / planning)

```sh
export UNIFI_API="https://unifi.example.com"   # provider env var for api_url
export UNIFI_API_KEY="…"
tofu init
tofu plan      # should report no changes against the live controller
```

Never commit `*.tfvars`, `*.tfstate*`, or `.terraform/` (see `.gitignore`).

## Roadmap

tofu-controller + plain Terraform is the pragmatic interim. The steady-state goal
is a real-CRD Crossplane provider (`provider-upjet-unifi`) so the network is
managed as native Kubernetes resources — tracked in the
[monorepo](https://github.com/devantler-tech/monorepo) issues.

## License

[Apache-2.0](LICENSE).
