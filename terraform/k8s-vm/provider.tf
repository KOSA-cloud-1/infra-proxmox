terraform {
  required_version = ">= 1.15.3, < 1.16.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.106.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.virtual_environment_endpoint
  api_token = var.virtual_environment_api_token
  insecure  = var.virtual_environment_insecure

  ssh {
    username    = var.proxmox_ssh_username
    agent       = var.proxmox_ssh_agent
    private_key = var.proxmox_ssh_agent ? null : file(pathexpand(var.proxmox_ssh_private_key_path))

    dynamic "node" {
      for_each = var.proxmox_ssh_nodes

      content {
        name    = node.key
        address = node.value.address
      }
    }
  }
}
