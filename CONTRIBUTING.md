# Contributing to the UniFi network configuration

You can help by clarifying an explanation or improving a focused manifest example.
Discuss substantial changes in an [issue](https://github.com/devantler-tech/unifi/issues)
first: this configuration describes one live home network and is consumed by the
portfolio's platform. Report sensitive vulnerabilities through this repository's private
[Report a vulnerability](https://github.com/devantler-tech/unifi/security/advisories/new)
form, not a public issue or PR.

## Make a first documentation change

You need Git and `kubectl` with built-in Kustomize. This first path needs no UniFi
controller, credentials, cluster or platform access.

Fork `devantler-tech/unifi` on GitHub. Replace `YOUR-LOGIN` with your login:

```sh
git clone https://github.com/YOUR-LOGIN/unifi.git
cd unifi
git switch -c docs/first-contribution
```

Make a small wording improvement in `README.md` without changing the render command or
the architecture it describes. From the repository root, run the local baseline:

```sh
kubectl kustomize . > /dev/null
git diff --check
```

Both commands must exit successfully and print nothing. The render validates the local
Kustomize build only. It does not check the resources against the provider's schemas,
reach the controller or prove anything about the live network.

[CI](.github/workflows/ci.yaml) repeats the render, runs `kubeconform` on it, checks every
field against the provider's CRD schema, and scans `README.md` and `AGENTS.md` for links to
retired repositories. The optional
`kubeconform` command and what its result means are in the
[README](README.md#render-locally). CI builds the link scanner from a released
revision, so you do not need to run it locally for a first change.

## Keep configuration and operations separate

Read [AGENTS.md](AGENTS.md) before changing a managed resource. Three rules matter most:

- **Leave the pause in place.** Every resource is held with `crossplane.io/paused` in
  `kustomization.yaml`, for the reasons in the
  [README](README.md#current-state-everything-here-is-paused). Do not remove it, and do
  not add a resource that must reconcile while the others are paused.
- **Adopt before you manage.** A resource for something that already exists on the
  controller must carry that object's id, so the first reconcile reads it instead of
  creating a duplicate. The [runbook](docs/runbook.md) has the procedure.
- **No secrets.** This repository is public. Credentials and keys live in the platform's
  secret store and are referenced by name only.

Applying these resources, moving the commit the platform pins and changing the
controller are maintainer operations, not onboarding steps. Do not apply this
configuration to a cluster or point a provider at a real controller to validate a first
PR.

## Submit your change

Review the diff, configure commit signing and stage only your changed paths. Use a
Conventional Commit subject describing the outcome. For the README-only first change
above:

```sh
git add README.md
git commit -S -m "docs: clarify the local render"
git push -u origin docs/first-contribution
```

Open a **draft** PR to `devantler-tech/unifi:main` using the inherited
[PR template](https://github.com/devantler-tech/.github/blob/main/.github/PULL_REQUEST_TEMPLATE.md).
Keep Why/What focused on the reader-facing problem and outcome, link the issue for
substantial work, and put detailed validation evidence in a PR comment or check summary.
Disclose AI assistance when used. Address findings; required CI and a successful
substantive review of the exact current head must pass before merge. Follow the inherited
[code of conduct](https://github.com/devantler-tech/.github/blob/main/.github/CODE_OF_CONDUCT.md)
and preserve the [Apache-2.0 license](LICENSE).
