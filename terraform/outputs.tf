# =========================================================
# Control Plane VM IDs
# =========================================================
output "cp_vm_ids" {
  description = "Control Plane VM ID 목록"
  value = {
    for k, vm in proxmox_virtual_environment_vm.cp :
    k => vm.vm_id
  }
}

# =========================================================
# Worker VM IDs
# =========================================================
output "worker_vm_ids" {
  description = "Worker VM ID 목록"
  value = {
    for k, vm in proxmox_virtual_environment_vm.worker :
    k => vm.vm_id
  }
}

# =========================================================
# Control Plane IP 정보
# =========================================================
output "cp_ips" {
  description = "Control Plane IP 목록 (관리망 / 내부망)"
  value = {
    for k, vm in var.cp_nodes :
    k => {
      mgmt     = vm.ip1g    # 관리망 (1G)
      internal = vm.ip10g   # 내부망 (10G)
    }
  }
}

# =========================================================
# Worker IP 정보
# =========================================================
output "worker_ips" {
  description = "Worker IP 목록 (관리망 / 내부망)"
  value = {
    for k, vm in var.worker_nodes :
    k => {
      mgmt     = vm.ip1g    # 관리망 (1G)
      internal = vm.ip10g   # 내부망 (10G)
    }
  }
}

# =========================================================
# Control Plane 노드 배치 정보
# =========================================================
output "cp_placement" {
  description = "CP VM이 어느 Proxmox 노드에 배치되었는지"
  value = {
    for k, vm in var.cp_nodes :
    k => vm.node
  }
}

# =========================================================
# Worker 노드 배치 정보
# =========================================================
output "worker_placement" {
  description = "Worker VM이 어느 Proxmox 노드에 배치되었는지"
  value = {
    for k, vm in var.worker_nodes :
    k => vm.node
  }
}

# =========================================================
# 전체 클러스터 요약
# =========================================================
output "cluster_summary" {
  description = "클러스터 전체 요약"
  value = {
    total_cp      = length(var.cp_nodes)
    total_workers = length(var.worker_nodes)
    total_vms     = length(var.cp_nodes) + length(var.worker_nodes)
    gateway       = var.gateway
  }
}