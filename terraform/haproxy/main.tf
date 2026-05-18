# =========================================================
# locals: keepalived unicast peer 목록 계산
# =========================================================
# 각 인스턴스 입장에서 "나를 제외한 나머지 인스턴스의 DMZ IP" 목록을 만들어
# keepalived unicast_peer 블록에 주입합니다.
locals {
  keepalived_peers = {
    for instance_name, instance in var.haproxy_instances :
    instance_name => {
      for peer_name, peer in var.haproxy_instances :
      peer_name => peer.ip1g
      if peer_name != instance_name
    }
  }
}

# =========================================================
# Cloud-init 설정 파일을 Proxmox datastore에 업로드
# =========================================================
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
      hostname               = each.key
      keepalived_auth_pass   = var.keepalived_auth_pass
      keepalived_interface   = var.keepalived_interface
      keepalived_peers       = values(local.keepalived_peers[each.key])
      keepalived_priority    = each.value.keepalived_priority
      keepalived_router_id   = var.keepalived_router_id
      keepalived_unicast_src = each.value.ip1g
      virtual_router_id      = var.keepalived_virtual_router_id
    })
    file_name = "haproxy-${each.key}-cloud-init.yml"
  }
}

# =========================================================
# HAProxy VM 생성
# =========================================================
resource "proxmox_virtual_environment_vm" "haproxy" {
  for_each = var.haproxy_instances

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

  clone {
    node_name = var.template_node_name
    vm_id     = var.template_vm_id
    full      = true
  }

  initialization {
    # eth0: DMZ (vmbr0, VLAN20, 1G) - HAProxy VIP 및 keepalived
    ip_config {
      ipv4 {
        address = "${each.value.ip1g}/${var.dmz_prefix_length}"
        gateway = var.dmz_gateway
      }
    }

    dns {
      servers = [var.dmz_gateway, "8.8.8.8"]
    }

    user_account {
      keys = [var.ssh_public_key]
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init[each.key].id
  }

  operating_system {
    type = "l26"
  }

  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    size         = each.value.disk_size
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  # eth0: DMZ VLAN20 (vmbr0, 1G) - HAProxy VIP 및 keepalived
  network_device {
    bridge  = var.dmz_bridge
    model   = "virtio"
    vlan_id = var.dmz_vlan_id
  }

  vga {
    type = "std"
  }

  lifecycle {
    ignore_changes = [
      network_device,
      disk,
    ]
  }
}
