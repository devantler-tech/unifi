# UniFi network — declarative configuration.
# =============================================================================
# Desired state of the UniFi network, reconciled continuously by tofu-controller
# on the platform (see README.md). Each concern is grouped into its own module
# under ./modules/; this file supplies the per-concern values and wires them
# together. The IMPORT-FIRST golden rule (docs/runbook.md) is enforced
# per-resource inside each module.
#
# STATUS: prepared, not yet applicable. The WireGuard client needs (1) a
# filipowm/unifi release with the vpn-client schema (#147) and (2) the platform
# Talos WireGuard server + internal admin gateway for the real peer/VIP values
# below. Provider docs: https://search.opentofu.org/provider/filipowm/unifi/latest
# =============================================================================

module "wireguard_vpn_client" {
  source = "./modules/wireguard-vpn-client"

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
