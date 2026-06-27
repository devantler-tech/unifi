variable "gateway_vip" {
  type        = string
  description = "Internal admin gateway VIP the hostnames resolve to (reachable only through the WireGuard tunnel)."
}

variable "hostnames" {
  type        = list(string)
  description = "Admin UI hostnames to resolve to the internal gateway VIP."
}
