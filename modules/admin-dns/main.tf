# Split-horizon local DNS: resolve the admin UI hostnames to the cluster's
# internal gateway VIP (reachable only through the WireGuard tunnel) instead of
# the public load balancer. Admin access is then VPN-only by topology — the VIP
# lives inside the WireGuard subnet, so the only route to it is the gateway
# tunnel, and no "force VPN" firewall rule is needed.
#
# import-first:new New local DNS records; these admin hostnames have no UniFi DNS record yet.
resource "unifi_dns_record" "this" {
  for_each = toset(var.hostnames)

  name        = each.value
  record_type = "A"
  value       = var.gateway_vip
}
