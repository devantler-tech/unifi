terraform {
  # Compatible with both OpenTofu (>= 1.6) and Terraform (>= 1.6). The cluster
  # reconciler is tofu-controller running OpenTofu.
  required_version = ">= 1.6"

  required_providers {
    unifi = {
      # ubiquiti-community/unifi: a plugin-framework provider for the UniFi
      # Controller (API-key auth, UDM/UDM-Pro/UCG) with first-class VPN
      # resources. https://github.com/ubiquiti-community/terraform-provider-unifi
      source  = "ubiquiti-community/unifi"
      version = "~> 0.53.0"
    }
  }

  # No backend block on purpose: tofu-controller manages state in a Kubernetes
  # Secret in the `unifi` namespace. For a local `tofu plan`, state stays local.
}
