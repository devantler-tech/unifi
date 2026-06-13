variable "unifi_api_url" {
  type        = string
  description = <<-EOT
    Base URL of the UniFi controller API. Do NOT include the `/api` path — the
    SDK discovers the correct paths (supports UDM-Pro style and standard
    controllers). Example: https://unifi.example.com
  EOT
}

variable "unifi_api_key" {
  type        = string
  sensitive   = true
  description = <<-EOT
    UniFi controller API key (requires controller >= 9.0.108). Use a dedicated
    service account with a Limited Admin, Local Access Only role. Supplied by
    the platform from `variables-cluster`; never commit it to this repo.
  EOT
}

variable "unifi_site" {
  type        = string
  default     = "default"
  description = "UniFi site this configuration manages."
}

variable "unifi_allow_insecure" {
  type        = bool
  default     = false
  description = "Skip TLS verification of the controller API. Set true only for a self-signed certificate."
}
