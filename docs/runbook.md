# Runbooks — operating the UniFi network as code

End-to-end procedures for the two operations that actually onboard and run this
network. Read [`README.md`](../README.md) first for the architecture and the
[`AGENTS.md`](../AGENTS.md) non-negotiables — the **import-first** golden rule
below is the repo's central safety property.

- [Runbook A — add a resource import-first](#runbook-a--add-a-resource-import-first)
- [Runbook B — service account & API-key rotation](#runbook-b--service-account--api-key-rotation)
- [Troubleshooting](#troubleshooting)

---

## Runbook A — add a resource import-first

> **Why:** this repo carries **no committed state** — tofu-controller owns state
> in-cluster. A `resource` block added without first importing the live object
> makes the very next `tofu apply` (run by the reconciler) **create or replace**
> it, which can wipe or duplicate live network config. Importing first makes the
> first plan a **no-op**; you only change the network once you choose to.

### The five steps

1. **Write the `resource`** to match what already exists on the controller.
   Start from the commented example in [`main.tf`](../main.tf).
2. **Find the live object's id** (the error-prone step — see below).
3. **Add a matching `import {}` block** whose `to` is the resource address and
   whose `id` is the live object id. Keep this block **permanently** — it is the
   under-management proof the CI guard (`scripts/check-import-first.sh`) checks,
   because a CLI `tofu import` leaves no trace in `*.tf`.
4. **`tofu plan`** and confirm it reports **No changes**. If it shows changes,
   the `resource` attributes don't match the live object yet — reconcile them
   (see [troubleshooting](#a-plan-shows-changes-right-after-an-import)) before
   going further. **Do not apply a plan that isn't a no-op.**
5. **Only now edit attributes** to actually change the network, in a follow-up
   commit, so the diff is purely your intended change.

### Finding the live object id

The Terraform id of a UniFi object is the controller's internal `_id`. Two ways
to get it, in order of reliability:

**A. Query the controller API (reliable, scriptable).** Use the same API key the
reconciler uses, against the REST config endpoints. On a UniFi OS console
(UDM/UDM-Pro/UCG) the Network application is proxied under `/proxy/network`:

```sh
# Networks (VLANs): id is the "_id" field, name is "name"
curl -sk -H "X-API-KEY: $UNIFI_API_KEY" \
  "$UNIFI_API/proxy/network/api/s/default/rest/networkconf" | jq '.data[] | {name, _id}'

# WLANs (SSIDs)
curl -sk -H "X-API-KEY: $UNIFI_API_KEY" \
  "$UNIFI_API/proxy/network/api/s/default/rest/wlanconf" | jq '.data[] | {name, _id}'
```

On a standalone/legacy controller drop the `/proxy/network` prefix and use the
`:8443` port: `https://<host>:8443/api/s/default/rest/networkconf`. Other config
collections follow the same pattern: `firewallrule`, `portforward`,
`portconf` (switch port profiles), `usergroup`. Swap `default` for your
`unifi_site` if you manage a non-default site.

**B. Read it from the UI.** Open the object in the controller (Settings →
Networks / WiFi), and the `_id` appears as the long hex string in the browser
URL while editing it.

Whichever you use, **step 4's no-op plan is the real safety net** — an id typo
surfaces there as an error or an unexpected diff, never as a silent live change.

### Worked example — a VLAN network and its WLAN

Say the controller already has an "IoT" VLAN (id `661f…a1`) and an "iot-ssid"
WiFi (id `662a…b9`). Bring both under management:

```hcl
# main.tf
resource "unifi_network" "iot" {
  name    = "IoT"
  purpose = "corporate"

  vlan_id      = 20
  subnet       = "10.0.20.1/24"
  dhcp_start   = "10.0.20.10"
  dhcp_stop    = "10.0.20.250"
  dhcp_enabled = true
}

import {
  to = unifi_network.iot
  id = "661f00000000000000000a1" # _id from /rest/networkconf
}

resource "unifi_wlan" "iot" {
  name       = "iot-ssid"
  security   = "wpapsk"
  passphrase = var.iot_wlan_passphrase # secret via variable — never hard-code
  network_id = unifi_network.iot.id
}

import {
  to = unifi_wlan.iot
  id = "662a00000000000000000b9" # _id from /rest/wlanconf
}
```

```sh
tofu plan   # MUST say "No changes" (other than reading the secret into state)
```

A WLAN passphrase (or any secret) is supplied as a variable from the platform —
declare the variable in `variables.tf` with `sensitive = true`; never commit the
value. If the plan is clean, commit the `resource` + `import {}` pair and open a
PR; the reconciler adopts the objects without touching them.

### Genuinely new objects (the one escape hatch)

If you are adding an object the network does **not** have yet (so there is
nothing to import), put a reviewed marker on the line **directly above** the
`resource` instead of an `import {}` block:

```hcl
# import-first:new brand-new guest VLAN, does not exist on the controller yet
resource "unifi_network" "guest" {
  # ...
}
```

The guard accepts `# import-first:new <reason>` as the audited exception. Use it
sparingly and only when the creation is intended — it is the one case where the
first apply is *meant* to create live config.

---

## Runbook B — service account & API-key rotation

The reconciler authenticates to the controller with an **API key** (UniFi
Controller **≥ 9.0.108**). Use a dedicated service account, never a personal
admin login.

### Create the service account + key

1. In the controller UI, open **Settings → Admins & Users** (older UniFi OS:
   **Control Plane → Admins**) and **add a new admin** for automation, e.g.
   `unifi-tofu`.
2. Give it the **Limited Admin** role with **Local Access Only** — it needs only
   network-configuration rights on this site, not full-console or remote/SSO
   access. Scope it to the site this repo manages.
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

### Where the key lives (the secret flow)

The key is **not** stored in this repo. It is provisioned by the
[platform](https://github.com/devantler-tech/platform), SOPS-encrypted:

```
controller (mint key)
   │  paste into the SOPS-encrypted value in platform `variables-cluster`
   ▼
platform variables-cluster (SOPS)  ──►  seeded into OpenBao (PushSecret)
   │  ExternalSecret in the `unifi` namespace
   ▼
tofu-controller Terraform CR  ──►  unifi_api_key variable  ──►  controller API
```

So onboarding the key is a **platform-side** change (edit the SOPS-encrypted
`variables-cluster` entry), not a change here. This repo only declares the
`unifi_api_key` variable (`sensitive = true`) and **must never** contain the
value or a committed `*.tfvars`.

### Rotate the key

1. On the controller, **create a new API key** on the `unifi-tofu` account
   (don't delete the old one yet).
2. Update the SOPS-encrypted `unifi_api_key` value in the platform
   `variables-cluster` and let the platform re-seed OpenBao; the ExternalSecret
   refreshes the in-cluster secret.
3. Confirm a reconcile still **no-ops** (the `Terraform` CR plans clean, or run a
   local `tofu plan` with the new key).
4. **Revoke the old key** on the controller.

Rotate on a schedule and immediately if a key is ever exposed. Because the key is
SOPS-encrypted and Local-Access-Only/Limited-Admin, blast radius is bounded to
this site's network config.

---

## Troubleshooting

Common reconcile failures (`Terraform` CR not ready, or a failing local
`tofu plan`) and their root cause:

### Auth fails (401 / "invalid API key") or a TLS handshake error
The `unifi_api_key` is wrong, expired/revoked, or the account lacks rights — or
the controller serves a **self-signed certificate**. Verify the key with the
read-only `curl` above. For a self-signed cert (only then), set
`unifi_allow_insecure = true` and justify it; prefer a valid TLS certificate.

### `api_url` contains `/api`
The provider/SDK **discovers** the API paths from the base URL, so a trailing
`/api` double-paths into 404s or a failed discovery. `unifi_api_url` must be the
bare base URL (e.g. `https://unifi.example.com`), never `…/api`.

### `tofu import` says the object is not found / the wrong object imports
The `id` isn't the live object's `_id`, or it's from the wrong site/collection.
Re-query the correct REST endpoint (`networkconf` vs `wlanconf` vs
`firewallrule` …) for the right site and copy the exact `_id`.

### A plan shows changes right after an import
The `resource` attributes don't match the live object. Inspect what actually
imported and align the HCL to it:

```sh
tofu state show unifi_network.iot   # the real, imported values
```

Set the differing attributes explicitly (or remove ones you didn't mean to
manage) until `tofu plan` is a clean no-op. **Never apply** a post-import plan
that still shows changes — that is exactly the live-config mutation import-first
exists to prevent.

### CI "Import-First Guard" fails
A `resource` was added without a matching `import {}` block **and** without an
`# import-first:new <reason>` marker. Add the import block (preferred) or, for a
genuinely new object, the reviewed marker. Run the guard locally before pushing:
`./scripts/check-import-first.sh`.
