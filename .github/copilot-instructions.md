# GitHub Copilot review instructions — unifi

`devantler-tech/unifi` is the **declarative desired state of the home UniFi
network**, written as plain OpenTofu/Terraform using the
[`filipowm/unifi`](https://github.com/filipowm/terraform-provider-unifi)
provider. It is reconciled continuously on the platform by **tofu-controller**
(a `Terraform` CR pulls this repo as a Flux `GitRepository`). Enforce the rules
below when reviewing. They complement `AGENTS.md` (the canonical, cross-tool
instructions) — keep both in sync.

## Safety — this changes a live network
- **Import-first.** A new resource must be brought under management with
  `tofu import` / an `import {}` block so its first plan is a **no-op**. Flag
  any PR that adds a `resource` for an object that already exists without a
  corresponding import — applying it can recreate/replace live network config.
  The `import {}` block is kept **permanently** as the under-management proof
  (CI runs `scripts/check-import-first.sh`); a genuinely new object is the only
  exception and must carry a reviewed `# import-first:new <reason>` marker.
- **No destructive drive-by changes.** Flag edits that would force-replace a
  `unifi_network`, `unifi_wlan`, or firewall resource (e.g. changing an
  immutable field) unless the PR body calls it out and it is intended.
- **Never weaken TLS silently.** `unifi_allow_insecure = true` is only for a
  self-signed controller cert and must be justified — flag unexplained `true`.

## Secrets & state
- **Never commit secrets.** Credentials (`unifi_api_key`, WLAN passphrases,
  RADIUS secrets) come from variables supplied by the platform — never
  hard-coded or in committed `*.tfvars`. Flag any literal secret.
- **Never commit state.** `*.tfstate*` must stay git-ignored; tofu-controller
  owns state in-cluster. Flag any state file or a `backend` block (the module
  must not declare one).

## Terraform hygiene
- Code must pass `tofu fmt -check -recursive`, `tofu validate` and `tflint`
  (recommended `terraform` ruleset) — flag formatting drift, invalid config,
  deprecated syntax and unused declarations.
- Pin the provider with a `~>` constraint in `versions.tf`; commit
  `.terraform.lock.hcl` so reconciles are reproducible. Flag an unpinned or
  removed provider constraint.
- `api_url` must NOT include the `/api` path (the SDK discovers paths). Flag a
  URL ending in `/api`.

## Commits, CI & actions
- **PR titles must be Conventional Commits** (`feat:`/`fix:`/`chore:`/`docs:`/
  `ci:`/`refactor:`) — the repo squash-merges the title into history. Flag
  violations and bracket prefixes.
- Workflow changes must pass `actionlint`; pin third-party actions to a
  full-length commit SHA and keep least-privilege `permissions:`. Flag unpinned
  actions and over-broad scopes.
- Never skip or weaken a check to make CI pass — fix the root cause.

Keep this file concise (≤ 4000 chars — Copilot review truncates beyond that)
and in sync with `AGENTS.md`.
