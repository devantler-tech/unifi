provider "unifi" {
  api_url = var.unifi_api_url
  api_key = var.unifi_api_key
  site    = var.unifi_site

  # Set true only for a controller with a self-signed certificate. Prefer a
  # valid TLS certificate and keep this false.
  allow_insecure = var.unifi_allow_insecure
}
