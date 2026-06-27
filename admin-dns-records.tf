# =============================================================================
# UniFi local DNS records for the cluster admin UIs.
#
# These A records resolve the admin/observability hostnames to the cluster's
# INTERNAL gateway VIP, which is reachable only through the WireGuard tunnel
# (see wireguard-vpn-client.tf). On the LAN/VPN they override public DNS
# (split-horizon), so the admin UIs are reached over the tunnel instead of the
# public load balancer.
#
# This is also why no "force VPN even at home" firewall rule is needed: the VIP
# lives inside the WireGuard subnet (10.200.0.0/24), so the only route to it is
# the gateway's tunnel. Access is enforced by topology, not by a firewall rule.
# (A stricter policy — e.g. limiting which LAN sources may use the tunnel — is a
# defense-in-depth decision best made alongside the internal-gateway design.)
#
# STATUS: prepared, NOT yet applicable.
#   WARNING: applying these BEFORE the internal gateway exists will BREAK admin
#   UI access on the LAN — the hostnames would resolve to a dead VIP. Apply only
#   after the platform internal admin gateway is serving admin_gateway_vip.
# unifi_dns_record is in the released provider, so this needs no provider
# release, only the internal gateway.
# =============================================================================

locals {
  # TODO(platform internal gateway): the internal-only Cilium gateway VIP inside
  # the WireGuard subnet that serves the admin UIs.
  admin_gateway_vip = "10.200.0.10"

  # The admin/observability UIs that move behind the internal gateway. Dex and
  # oauth2-proxy intentionally stay public (they are the OIDC issuer / SSO proxy).
  admin_ui_hostnames = [
    "observability.platform.devantler.tech", # Coroot
    "hubble.platform.devantler.tech",        # Cilium Hubble
    "ksail.platform.devantler.tech",         # KSail
    "vault.platform.devantler.tech",         # OpenBao
    "opencost.platform.devantler.tech",      # OpenCost
    "longhorn.platform.devantler.tech",      # Longhorn
    "headlamp.platform.devantler.tech",      # Headlamp
  ]
}

# import-first:new New local DNS records; these admin hostnames have no UniFi DNS record yet.
resource "unifi_dns_record" "admin_ui" {
  for_each = toset(local.admin_ui_hostnames)

  name   = each.value
  type   = "A"
  record = local.admin_gateway_vip
}
