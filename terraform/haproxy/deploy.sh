#!/bin/bash
set -e  # 에러 발생 시 즉시 중단

echo "======================================"
echo "1단계: Cloud-init snippet 업로드"
echo "======================================"
# VM 생성 전에 cloud-init 파일을 Proxmox datastore에 먼저 올려야 함
terraform apply -target='proxmox_virtual_environment_file.cloud_init' -auto-approve

echo ""
echo "======================================"
echo "2단계: HAProxy VM 생성"
echo "======================================"
terraform apply -target='proxmox_virtual_environment_vm.haproxy' -auto-approve

echo ""
echo "======================================"
echo "✅ 모든 VM 생성 완료!"
echo "======================================"
