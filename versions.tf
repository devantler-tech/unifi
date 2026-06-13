terraform {
  # Compatible with both OpenTofu (>= 1.6) and Terraform (>= 1.6). The cluster
  # reconciler is tofu-controller running OpenTofu.
  required_version = ">= 1.6"

  required_providers {
    unifi = {
      # Maintained fork of paultyng/unifi: API-key auth, UniFi Controller v6+
      # (incl. v9.x), UDM/UDM-Pro/UCG. https://github.com/filipowm/terraform-provider-unifi
      source  = "filipowm/unifi"
      version = "~> 1.0"
    }
  }

  # No backend block on purpose: tofu-controller manages state in a Kubernetes
  # Secret in the `unifi` namespace. For a local `tofu plan`, state stays local.
}
