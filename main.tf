# UniFi network — declarative configuration
# =============================================================================
# This repo is the desired state of the UniFi network. It is reconciled
# continuously by tofu-controller on the platform (see README.md). The
# golden rule is IMPORT-FIRST: never let a first apply create or destroy live
# network config. Bring existing objects under management with `tofu import`
# (or an `import {}` block) so the plan is a no-op, then evolve from there.
#
# Workflow to add a real resource:
#   1. Uncomment / write the resource below to match what already exists.
#   2. Import it:  tofu import unifi_network.lan <network-id>
#      (or add an `import { to = ...  id = ... }` block).
#   3. Run `tofu plan` and confirm it shows NO changes.
#   4. Only then start editing attributes to change the network.
#
# Until a resource is added, this configuration is intentionally empty and
# `tofu plan` reports "No changes" — a safe no-op against any controller.
# Provider docs: https://search.opentofu.org/provider/filipowm/unifi/latest
# =============================================================================

# ---------------------------------------------------------------------------
# Example (commented). Uncomment + import to start managing a VLAN network.
# ---------------------------------------------------------------------------
# resource "unifi_network" "iot" {
#   name    = "IoT"
#   purpose = "corporate"
#
#   vlan_id      = 20
#   subnet       = "10.0.20.1/24"
#   dhcp_start   = "10.0.20.10"
#   dhcp_stop    = "10.0.20.250"
#   dhcp_enabled = true
# }

# resource "unifi_wlan" "iot" {
#   name       = "iot-ssid"
#   security   = "wpapsk"
#   passphrase = var.example_secret # pass secrets via variables, never hard-code
#   network_id = unifi_network.iot.id
# }
