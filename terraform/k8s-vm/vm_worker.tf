resource "proxmox_virtual_environment_vm" "worker" {
  for_each = var.worker_nodes

  name      = each.key
  vm_id     = each.value.id
  node_name = each.value.node
  started   = true

  machine = "q35"
  bios    = "ovmf"

  efi_disk {
    datastore_id = var.vm_datastore_id
    file_format  = "raw"
    type         = "4m"
  }

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cpu
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
    floating  = each.value.balloon
  }

  operating_system {
    type = "l26"
  }

  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    size         = 20
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  # net0: 관리망 (vmbr0, VLAN40, 1G)
  network_device {
    bridge  = var.mgmt_bridge
    model   = "virtio"
    vlan_id = var.mgmt_vlan_id
  }

  # net1: Kubernetes 내부망 (vmbr1, 10G)
  network_device {
    bridge = var.internal_bridge
    model  = "virtio"
  }

  vga {
    type = "std"
  }

  clone {
    node_name = var.template_node_name
    vm_id     = var.template_vm_id
    full      = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip1g}/${var.mgmt_prefix_length}"
        gateway = var.gateway
      }
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip10g}/${var.internal_prefix_length}"
      }
    }

    dns {
      servers = [var.gateway, "8.8.8.8"]
    }

    user_account {
      keys = [var.ssh_public_key]
    }

    user_data_file_id = "local:snippets/init-${each.key}.yml"
  }

  lifecycle {
    ignore_changes = [
      network_device,
      disk,
    ]
  }
}
