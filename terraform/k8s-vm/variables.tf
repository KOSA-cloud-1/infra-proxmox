# =========================================================
# Proxmox API 접속 정보
# =========================================================
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
    team11 = { address = "192.168.36.151" }
    team12 = { address = "192.168.36.152" }
    team13 = { address = "192.168.36.153" }
    team14 = { address = "192.168.36.154" }
  }
}

# =========================================================
# Template 정보
# =========================================================
variable "template_vm_id" {
  description = "Clone에 사용할 Template VM ID"
  type        = number
}

variable "template_name" {
  description = "Template 이름"
  type        = string
}

variable "template_node_name" {
  description = "Template VM이 존재하는 Proxmox 노드"
  type        = string
  default     = "team14"
}

# =========================================================
# SSH 설정
# =========================================================
variable "ssh_public_key" {
  description = "VM에 주입할 SSH 공개 키"
  type        = string
  sensitive   = true
}

# =========================================================
# Storage
# =========================================================
variable "vm_datastore_id" {
  description = "VM OS 디스크 및 EFI 디스크 datastore"
  type        = string
  default     = "ceph-rbd"
}

variable "cp_etcd_datastore_id" {
  description = "Control Plane 전용 etcd 추가 디스크 datastore"
  type        = string
  default     = "local-lvm"
}

# =========================================================
# 네트워크 설정
# =========================================================
variable "gateway" {
  description = "관리망 (1G, vmbr0) 기본 게이트웨이"
  type        = string
}

variable "mgmt_bridge" {
  description = "관리망 (1G) Proxmox bridge"
  type        = string
  default     = "vmbr0"
}

variable "mgmt_vlan_id" {
  description = "Kubernetes 관리망 VLAN ID"
  type        = number
  default     = 40
}

variable "mgmt_prefix_length" {
  description = "관리망 서브넷 prefix length"
  type        = number
  default     = 22
}

variable "internal_bridge" {
  description = "Kubernetes 내부망 (10G) Proxmox bridge"
  type        = string
  default     = "vmbr1"
}

variable "internal_prefix_length" {
  description = "Kubernetes 내부망 서브넷 prefix length"
  type        = number
  default     = 24
}

# =========================================================
# Kubernetes VM 구성
# =========================================================
variable "cp_nodes" {
  description = "생성할 Control Plane VM 목록"

  type = map(object({
    id      = number
    node    = string
    ip1g    = string
    ip10g   = string
    cpu     = number
    memory  = number
    balloon = optional(number, 512)
  }))
}

variable "worker_nodes" {
  description = "생성할 Worker Node VM 목록"

  type = map(object({
    id      = number
    node    = string
    ip1g    = string
    ip10g   = string
    cpu     = number
    memory  = number
    balloon = optional(number, 512)
  }))
}
