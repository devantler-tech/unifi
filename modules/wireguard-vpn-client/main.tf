# WireGuard VPN client: the UniFi gateway dials a remote WireGuard server so
# home/LAN traffic reaches the cluster's internal networks over an encrypted
# tunnel instead of exposing them publicly.
#
# The gateway's key pair is generated out-of-band (`wg genkey | wg pubkey`):
# the private key is supplied here (sensitive), and its matching public key is
# added as a peer on the remote server.

# import-first:new Brand-new WireGuard VPN client; the controller has none yet.
resource "unifi_vpn_client" "this" {
  name   = var.name
  subnet = var.tunnel_address # the gateway's local tunnel interface address

  default_route = false # only the routes below go over the tunnel
  pull_dns      = false

  wireguard = {
    private_key = var.private_key
    interface   = var.egress_interface
    dns_servers = var.interface_dns

    peer = {
      ip         = var.peer_endpoint
      port       = var.peer_port
      public_key = var.peer_public_key
    }
  }
}

# Route only the cluster networks through the tunnel (not all internet traffic).
# import-first:new Brand-new traffic route; the controller has none yet.
resource "unifi_traffic_route" "cluster" {
  description = "Route cluster networks through the WireGuard VPN client."
  network_id  = unifi_vpn_client.this.id

  destination = {
    ip = [for cidr in var.routes : { address = cidr }]
  }
}
