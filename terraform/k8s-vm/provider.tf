# 사용할 프로바이더와 버전 설정
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
  insecure  = true

  ssh {
    username    = "root"
    agent       = false
    private_key = file(pathexpand("~/.ssh/id_team1_sunmin"))

    node {
      name    = "team11"
      address = "192.168.36.151"
    }
    node {
      name    = "team12"
      address = "192.168.36.152"
    }
    node {
      name    = "team13"
      address = "192.168.36.153"
    }
    node {
      name    = "team14"
      address = "192.168.36.154"
    }
  }
}
