variable "virtual_environment_endpoint" {
  description = "Proxmox API Endpoint"
  type        = string
}

variable "virtual_environment_api_token" {
  description = "Proxmox API Token"
  type        = string
  sensitive   = true
}

variable "virtual_environment_insecure" {
  description = "Proxmox API TLS 검증 비활성화 여부"
  type        = bool
  default     = true
}

variable "proxmox_ssh_username" {
  description = "Proxmox 노드 SSH 사용자"
  type        = string
  default     = "root"
}

variable "proxmox_ssh_agent" {
  description = "Proxmox 노드 SSH 접속에 ssh-agent를 사용할지 여부"
  type        = bool
  default     = false
}

variable "proxmox_ssh_private_key_path" {
  description = "Proxmox 노드 SSH Private Key 경로"
  type        = string
  default     = "~/.ssh/id_team1_sunmin"
}

variable "proxmox_ssh_nodes" {
  description = "Proxmox 노드 SSH 접속 정보"

  type = map(object({
    address = string
  }))

  default = {
    team11 = {
      address = "192.168.36.151"
    }
    team12 = {
      address = "192.168.36.152"
    }
    team13 = {
      address = "192.168.36.153"
    }
    team14 = {
      address = "192.168.36.154"
    }
  }
}

variable "template_vm_id" {
  description = "Clone에 사용할 Template VM ID"
  type        = number
}

variable "template_node_name" {
  description = "Template VM이 존재하는 Proxmox 노드"
  type        = string
  default     = "team14"
}

variable "vm_datastore_id" {
  description = "HAProxy VM 디스크 datastore"
  type        = string
  default     = "ceph-rbd"
}

variable "snippet_datastore_id" {
  description = "Cloud-init snippet을 업로드할 datastore"
  type        = string
  default     = "local"
}

variable "ssh_public_key" {
  description = "HAProxy VM에 주입할 SSH 공개 키"
  type        = string
  sensitive   = true
}

variable "dmz_bridge" {
  description = "DMZ VLAN이 연결된 Proxmox bridge (1G, vmbr0)"
  type        = string
  default     = "vmbr0"
}

variable "dmz_vlan_id" {
  description = "On-Prem HAProxy가 위치할 DMZ VLAN ID"
  type        = number
  default     = 20
}

variable "dmz_prefix_length" {
  description = "DMZ VLAN subnet prefix length"
  type        = number
  default     = 24
}

variable "dmz_gateway" {
  description = "DMZ VLAN gateway. pfSense OPT2 기본값은 172.17.32.1입니다."
  type        = string
  default     = "172.17.32.1"
}

variable "haproxy_vip" {
  description = "VLAN20 DMZ에서 keepalived가 제공할 On-Prem HAProxy VIP"
  type        = string
}

variable "ingress_vip" {
  description = "VLAN40 Kubernetes Ingress VIP. HAProxy backend 대상입니다."
  type        = string
}

variable "haproxy_instances" {
  description = "생성할 On-Prem HAProxy VM 목록"

  type = map(object({
    id                  = number
    node                = string
    ip1g                = string # DMZ IP (eth0, vmbr0, 1G)
    cpu                 = optional(number, 2)
    memory              = optional(number, 2048)
    balloon             = optional(number, 512)
    disk_size           = optional(number, 20)
    keepalived_priority = optional(number, 100)
  }))
}

variable "haproxy_balance_algorithm" {
  description = "Ingress backend balance 알고리즘"
  type        = string
  default     = "roundrobin"
}

variable "haproxy_maxconn" {
  description = "HAProxy global maxconn 값"
  type        = number
  default     = 4096
}

variable "keepalived_interface" {
  description = "VRRP VIP를 올릴 VM 내부 NIC 이름"
  type        = string
  default     = "eth0"
}

variable "keepalived_router_id" {
  description = "keepalived router_id"
  type        = string
  default     = "onprem_haproxy"
}

variable "keepalived_virtual_router_id" {
  description = "VRRP virtual_router_id. 동일 L2 구간에서 중복되지 않아야 합니다."
  type        = number
  default     = 20
}

variable "keepalived_auth_pass" {
  description = "VRRP authentication password. 8자 이하를 권장합니다."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.keepalived_auth_pass) <= 8
    error_message = "keepalived_auth_pass는 keepalived auth_pass 제한에 맞춰 8자 이하여야 합니다."
  }
}
