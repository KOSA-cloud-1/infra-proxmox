output "vm_ids" {
  value = {
    for k, vm in proxmox_virtual_environment_vm.k8s :
    k => vm.vm_id
  }
}

output "vm_ips" {
  value = {
    for k, vm in var.virtual_machines :
    k => vm.ip
  }
}