# Runbooks — operating the UniFi network as code

End-to-end procedures for the operations that onboard and run this network. Read
[`README.md`](../README.md) first for the architecture and the
[`AGENTS.md`](../AGENTS.md) non-negotiables — the **adopt-first** golden rule below
is the repo's central safety property.

- [Runbook A — add a resource adopt-first](#runbook-a--add-a-resource-adopt-first)
- [Runbook B — service account & API-key rotation](#runbook-b--service-account--api-key-rotation)
- [Troubleshooting](#troubleshooting)

---

## Runbook A — add a resource adopt-first

> **Why:** a Managed Resource reconciles toward the controller continuously. If you
> add one for an object that **already exists** without telling Crossplane which
> live object it is, the provider creates a **duplicate** (or, on a name clash,
> errors). Adopting first — binding the MR to the live object's id — makes the first
> reconcile a **no-op read**; you only change the network once you choose to. A
> genuinely **new** object (nothing to adopt) is simply created — that is the normal
> case for everything shipped here today.

### Adopt an existing object

1. **Write the Managed Resource** to match what already exists on the controller.
2. **Find the live object's id** (the error-prone step — see below).
3. **Annotate it** `crossplane.io/external-name: <unifi-id>` so Crossplane binds to
   the live object instead of creating a new one.
4. **(Safest) observe first.** Set `spec.managementPolicies: ["Observe"]` and let it
   reconcile; confirm `kubectl get -n unifi <kind> <name> -o yaml` shows
   `Synced=True`, `Ready=True`, and a `.status.atProvider` that matches the live
   object. **Only then** remove the policy (or set it back to `["*"]`) to manage it.
5. **Only now edit fields** to actually change the network, in a follow-up commit, so
   the diff is purely your intended change.

### Create a new object

Nothing to adopt → no `external-name` annotation. Write the Managed Resource and let
Crossplane create it. Everything in this repo today (the WireGuard `Client`, its
`TrafficRoute`, the admin DNS `Record`s) is new, so it is created on first reconcile.

### Finding the live object id

The Crossplane external-name of a UniFi object is the controller's internal `_id`.
Two ways to get it, in order of reliability:

**A. Query the controller API (reliable, scriptable).** Use the same API key the
provider uses, against the REST config endpoints. On a UniFi OS console
(UDM/UDM-Pro/UCG) the Network application is proxied under `/proxy/network`:

```sh
# Networks/VPN clients (the VPN client is a network): id is "_id", name is "name"
curl -sk -H "X-API-KEY: $UNIFI_API_KEY" \
  "$UNIFI_API/proxy/network/api/s/default/rest/networkconf" | jq '.data[] | {name, _id}'

# DNS records
curl -sk -H "X-API-KEY: $UNIFI_API_KEY" \
  "$UNIFI_API/proxy/network/api/s/default/rest/dnsrecord" | jq '.data[] | {key, _id}'
```

On a standalone/legacy controller drop the `/proxy/network` prefix and use the
`:8443` port: `https://<host>:8443/api/s/default/rest/networkconf`. Other config
collections follow the same pattern: `firewallrule`, `portforward`, `wlanconf`,
`trafficroute`. Swap `default` for your site if you manage a non-default one.

**B. Read it from the UI.** Open the object in the controller and the `_id` appears
as the long hex string in the browser URL while editing it.

Whichever you use, **step 4's Observe reconcile is the real safety net** — an id typo
surfaces there as a `Synced=False` error or a mismatched `.status.atProvider`, never
as a silent live change.

### Worked example — adopt an existing DNS record

Say the controller already has an `A` record for `nas.lan` (id `661f…a1`). Bring it
under management without changing it:

```yaml
apiVersion: dns.unifi.m.crossplane.io/v1alpha1
kind: Record
metadata:
  name: nas
  annotations:
    crossplane.io/external-name: "661f00000000000000000a1" # _id from /rest/dnsrecord
spec:
  managementPolicies: ["Observe"] # read-only until verified, then remove
  forProvider:
    name: nas.lan
    recordType: A
    value: 10.0.0.20
  providerConfigRef:
    kind: ProviderConfig
    name: default
```

```sh
kubectl get -n unifi record.dns.unifi.m.crossplane.io nas -o yaml
# want: Synced=True, Ready=True, .status.atProvider matching the live record
```

A secret value (a WireGuard key, a WLAN passphrase, …) is never inlined — reference a
Secret produced by the platform's External Secrets (e.g. the VPN client's
`privateKeySecretRef`). If Observe is clean, drop the policy, commit, and open a PR;
the reconciler then manages the object without recreating it.

---

## Runbook B — service account & API-key rotation

The provider authenticates to the controller with an **API key** (UniFi Controller
**≥ 9.0.108**). Use a dedicated service account, never a personal admin login.

### Create the service account + key

1. In the controller UI, open **Settings → Admins & Users** (older UniFi OS:
   **Control Plane → Admins**) and **add a new admin** for automation, e.g.
   `unifi-crossplane`.
2. Give it the **Limited Admin** role with **Local Access Only** — it needs only
   network-configuration rights on this site, not full-console or remote/SSO access.
3. As that account, **create an API key** (UniFi OS ≥ 9: the admin's profile →
   **Create API Key**). Copy the key once — it is shown only at creation.
4. Sanity-check it read-only before wiring it in:

   ```sh
   export UNIFI_API="https://unifi.example.com"   # base URL, NO /api suffix
   export UNIFI_API_KEY="…"
   curl -sk -H "X-API-KEY: $UNIFI_API_KEY" \
     "$UNIFI_API/proxy/network/api/s/default/rest/networkconf" | jq '.meta'
   # -> { "rc": "ok" }
   ```

### Where the credentials live (the secret flow)

The key is **not** stored in this repo. It lives in
[platform](https://github.com/devantler-tech/platform)'s **OpenBao** and is read
into the cluster by an ExternalSecret that renders Crossplane's `ProviderConfig`
credentials Secret:

```text
controller (mint key)
   │  write the real value IN PLACE (OpenBao UI/CLI)
   ▼
OpenBao  secret/infrastructure/unifi/controller  { api_url, api_key }
   │  platform `vault-config` Job seeds PLACEHOLDERS here on first run (only if absent)
   │  ExternalSecret in the `unifi` namespace renders the credentials JSON (refresh 1h)
   ▼
Secret (unifi-controller-credentials)  ◄── ProviderConfig.spec.credentials.secretRef
   │
   ▼
provider-upjet-unifi  ──►  controller API
```

The platform `vault-config` Job seeds **placeholder** values at
`secret/infrastructure/unifi/controller`, but only when that path is absent — so a
re-run never clobbers a real value (the same pattern as the GitHub App creds).
Onboarding the key is therefore an **OpenBao** change — *not* a repo change:
overwrite the placeholders in place via the OpenBao UI or CLI, e.g.

```sh
bao kv put -mount=secret infrastructure/unifi/controller \
  api_url="https://unifi.example.com" \
  api_key="…"   # base URL has NO /api suffix; Limited-Admin, Local-Access-Only key
```

The ExternalSecret refreshes within the hour (or force a sync) and renders the
credentials Secret as the JSON blob the provider forwards to the underlying SDK:
`{"api_url": "...", "api_key": "...", "site": "default", "allow_insecure":
"false"}`. The WireGuard `Client` additionally reads a `cluster-wireguard` Secret in
the `unifi` namespace — the gateway's `private-key` (sensitive) and the Talos
server's `peer-public-key` — also seeded from OpenBao. So onboarding credentials is a
**platform-side** change (the `ProviderConfig`, the External Secrets, and the OpenBao
seed live in the platform's `apps/unifi/`), not a change here. This repo only
references them by name and **must never** contain a value.

### Rotate the key

1. On the controller, **create a new API key** on the `unifi-crossplane` account
   (don't delete the old one yet).
2. Overwrite the `api_key` at `secret/infrastructure/unifi/controller` in OpenBao
   (UI/CLI, in place); the ExternalSecret refreshes the in-cluster credentials
   Secret within the hour.
3. Confirm the Managed Resources still reconcile clean (`Synced=True` / `Ready=True`,
   no spurious diff).
4. **Revoke the old key** on the controller.

Rotate on a schedule and immediately if a key is ever exposed. Because the key
lives only in OpenBao (encrypted at rest, backed up via Raft snapshots) and is
Local-Access-Only/Limited-Admin, blast radius is bounded to this site's network
config.

---

## Troubleshooting

Common reconcile failures (a Managed Resource stuck `Synced=False` or `Ready=False`)
and their root cause. Inspect with:

```sh
kubectl get -n unifi managed                       # all UniFi MRs + SYNCED/READY
kubectl describe -n unifi client.vpn.unifi.m.crossplane.io cluster-wireguard
```

### Auth fails (401 / "invalid API key") or a TLS handshake error
The `api_key` in the credentials Secret is wrong, expired/revoked, or the account
lacks rights — or the controller serves a **self-signed certificate**. Verify the key
with the read-only `curl` above. For a self-signed cert (only then), set
`allow_insecure: "true"` in the platform's credentials JSON and justify it; prefer a
valid TLS certificate.

### `api_url` contains `/api`
The provider/SDK **discovers** the API paths from the base URL, so a trailing `/api`
double-paths into 404s. The credentials `api_url` must be the bare base URL (e.g.
`https://unifi.example.com`), never `…/api`.

### A `Client` is stuck without a handshake / the routes don't apply
The `TrafficRoute.spec.forProvider.networkId` must be the VPN client's UniFi network
id, which is only known **after** the `Client` first reconciles — read it from the
`Client`'s `.status.atProvider.id` (or `/rest/networkconf`) and set it. The peer
`ip` must be the reachable control-plane endpoint and `port` `51820`. (A
cross-resource reference that wires this automatically is tracked upstream in
`provider-upjet-unifi`.)

### A reconcile wants to create an object that already exists (duplicate)
The Managed Resource is missing its `crossplane.io/external-name` annotation, so
Crossplane is trying to create rather than adopt. Add the annotation with the live
object's `_id` (see [Runbook A](#finding-the-live-object-id)); for extra safety set
`managementPolicies: ["Observe"]` first and verify `.status.atProvider`.

### A Secret reference doesn't resolve
`privateKeySecretRef` / `publicKeySecretRef` are **local** references — the Secret
must exist in the **same namespace** (`unifi`) as the Managed Resource, with the
referenced key. Confirm the platform's External Secret has materialised it:
`kubectl get secret -n unifi cluster-wireguard -o jsonpath='{.data}'`.

### The provider itself isn't healthy
If every MR is `Synced=False`, check the provider package and config:
`kubectl get providers,providerconfigs.unifi.m.crossplane.io -A` and the provider
pod logs in `crossplane-system`. The `Provider` package + `ProviderConfig` are
installed by the platform.
