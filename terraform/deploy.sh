#!/bin/bash
set -e  # 에러 발생 시 즉시 중단

echo "======================================"
echo "1단계: Control Plane 생성 시작"
echo "======================================"
terraform apply -target='proxmox_virtual_environment_vm.cp' -auto-approve 

echo ""
echo "======================================"
echo "2단계: Worker Node 생성 시작"
echo "======================================"
terraform apply -target='proxmox_virtual_environment_vm.worker' -auto-approve -parallelism=2

echo ""
echo "======================================"
echo "✅ 모든 VM 생성 완료!"
echo "======================================"