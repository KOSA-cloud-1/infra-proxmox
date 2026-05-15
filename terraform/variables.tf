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

# =========================================================
# VM 사용자 정보
# =========================================================

#variable "vm_user" {
#  description = "VM 기본 사용자 계정"
#  type        = string
#}

#variable "vm_password" {
#  description = "VM 사용자 비밀번호"
#  type        = string
#  sensitive   = true
#}

# =========================================================
# SSH 설정
# =========================================================

variable "ssh_public_key" {
  description = "VM에 주입할 SSH 공개 키"
  type        = string
  sensitive   = true
}

# =========================================================
# Kubernetes VM 구성
# =========================================================

variable "cp_nodes" {
  type = map(object({
    id     = number
    node   = string
    ip1g   = string
    ip10g  = string
    cpu    = number
    memory = number
  }))
}

variable "worker_nodes" {
  type = map(object({
    id     = number
    node   = string
    ip1g   = string
    ip10g  = string
    cpu    = number
    memory = number
  }))
}

variable "gateway" {
  type        = string
}