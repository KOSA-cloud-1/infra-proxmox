locals {
  keepalived_peers = {
    for instance_name, instance in var.haproxy_instances :
    instance_name => {
      for peer_name, peer in var.haproxy_instances :
      peer_name => peer.ip
      if peer_name != instance_name
    }
  }
}

resource "proxmox_virtual_environment_file" "cloud_init" {
  for_each = var.haproxy_instances

  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = each.value.node

  source_raw {
    data = templatefile("${path.module}/templates/cloud-init.yml.tftpl", {
      dmz_prefix_length = var.dmz_prefix_length
      haproxy_config = templatefile("${path.module}/templates/haproxy.cfg.tftpl", {
        balance_algorithm = var.haproxy_balance_algorithm
        frontend_ip       = var.haproxy_vip
        ingress_vip       = var.ingress_vip
        maxconn           = var.haproxy_maxconn
      })
      haproxy_vip            = var.haproxy_vip
      keepalived_auth_pass   = var.keepalived_auth_pass
      keepalived_interface   = var.keepalived_interface
      keepalived_peers       = values(local.keepalived_peers[each.key])
      keepalived_priority    = each.value.keepalived_priority
      keepalived_router_id   = var.keepalived_router_id
      keepalived_unicast_src = each.value.ip
      virtual_router_id      = var.keepalived_virtual_router_id
    })
    file_name = "haproxy-${each.key}-cloud-init.yml"
  }
}

resource "proxmox_virtual_environment_vm" "haproxy" {
  for_each = var.haproxy_instances

  name      = each.key
  vm_id     = each.value.id
  node_name = each.value.node
  started   = true

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cpu
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  clone {
    node_name = var.template_node_name
    vm_id     = var.template_vm_id
    full      = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.dmz_prefix_length}"
        gateway = var.dmz_gateway
      }
    }

    user_account {
      keys = [var.ssh_public_key]
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init[each.key].id
  }

  operating_system {
    type = "l26"
  }

  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["scsi0"]

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    size         = each.value.disk_size
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  network_device {
    bridge  = var.dmz_bridge
    model   = "virtio"
    vlan_id = var.dmz_vlan_id
  }

  vga {
    type = "std"
  }
}
