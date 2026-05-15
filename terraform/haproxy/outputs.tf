output "haproxy_vm_ids" {
  description = "On-Prem HAProxy VM ID 목록"
  value = {
    for k, vm in proxmox_virtual_environment_vm.haproxy :
    k => vm.vm_id
  }
}

output "haproxy_dmz_ips" {
  description = "On-Prem HAProxy DMZ IP 목록"
  value = {
    for k, vm in var.haproxy_instances :
    k => vm.ip
  }
}

output "haproxy_vip" {
  description = "VLAN20 DMZ HAProxy VIP"
  value       = var.haproxy_vip
}

output "ingress_vip" {
  description = "VLAN40 Kubernetes Ingress VIP"
  value       = var.ingress_vip
}
