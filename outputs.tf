output "cluster_wireguard_gateway_public_key" {
  description = "The gateway's WireGuard public key; add it as a peer on the Talos WG server."
  value       = module.wireguard_vpn_client.gateway_public_key
}
