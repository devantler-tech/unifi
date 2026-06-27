variable "egress_interface" {
  type        = string
  default     = "wan"
  description = "WAN interface the tunnel egresses from (`wan` or `wan2`)."
}

variable "interface_dns" {
  type        = list(string)
  default     = ["1.1.1.1"]
  description = "Tunnel interface DNS. Required by the controller for a wireguard-client."
}

variable "name" {
  type        = string
  default     = "cluster-wireguard"
  description = "Name of the UniFi vpn-client network."
}

variable "peer_endpoint" {
  type        = string
  description = "Host or IP of the remote WireGuard server the gateway dials."
}

variable "peer_port" {
  type        = number
  default     = 51820
  description = "Listen port of the remote WireGuard server."
}

variable "peer_public_key" {
  type        = string
  description = "Public key of the remote WireGuard server (the Talos control plane)."
}

variable "routes" {
  type        = list(string)
  description = "Destination subnets (CIDR) routed through the tunnel. `vpn_client_default_route` stays false, so only these go over the VPN."
}

variable "tunnel_address" {
  type        = string
  description = "The gateway's own address on the WireGuard tunnel, in CIDR (e.g. `10.200.0.2/32`)."
}
