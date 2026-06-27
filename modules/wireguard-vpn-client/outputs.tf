output "gateway_public_key" {
  description = "The gateway's WireGuard public key; add it as a peer on the remote server."
  value       = unifi_network.this.wireguard_public_key
}
