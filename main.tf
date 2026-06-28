# UniFi network — declarative configuration.
# =============================================================================
# Desired state of the UniFi network, reconciled continuously by tofu-controller
# on the platform (see README.md). Each concern is grouped into its own module
# under ./modules/; this file supplies the per-concern values and wires them
# together. The IMPORT-FIRST golden rule (docs/runbook.md) is enforced
# per-resource inside each module.
#
# STATUS: prepared, pending the platform WireGuard server. The provider and its
# VPN resources are released, so this validates and is mergeable today; applying
# it needs (1) the Talos control-plane WireGuard server for the real peer
# endpoint/public key (placeholders below) and the gateway's private key (a
# sensitive variable, seeded into OpenBao), and (2) the internal admin gateway
# for the DNS VIP. Provider docs:
# https://search.opentofu.org/provider/ubiquiti-community/unifi/latest
# =============================================================================

module "wireguard_vpn_client" {
  source = "./modules/wireguard-vpn-client"

  # The gateway's own WireGuard private key (sensitive; supplied by the platform).
  private_key = var.gateway_wireguard_private_key

  # TODO(platform WG server): real values once the Talos control-plane WireGuard
  # server exists. Both are non-secret (a public key and a public endpoint).
  peer_public_key = "REPLACE_WITH_TALOS_WG_SERVER_PUBLIC_KEY"
  peer_endpoint   = "REPLACE_WITH_CONTROL_PLANE_PUBLIC_IP"
  tunnel_address  = "10.200.0.2/32"
  routes = [
    "10.200.0.0/24", # WireGuard subnet
    "10.0.0.0/16",   # Hetzner nodes
    "10.244.0.0/16", # pods
  ]
}

module "admin_dns" {
  source = "./modules/admin-dns"

  # TODO(platform internal gateway): the internal-only VIP these hostnames
  # resolve to. Dex and oauth2-proxy intentionally stay public.
  gateway_vip = "10.200.0.10"
  hostnames = [
    "observability.platform.devantler.tech", # Coroot
    "hubble.platform.devantler.tech",
    "ksail.platform.devantler.tech",
    "vault.platform.devantler.tech", # OpenBao
    "opencost.platform.devantler.tech",
    "longhorn.platform.devantler.tech",
    "headlamp.platform.devantler.tech",
  ]
}
