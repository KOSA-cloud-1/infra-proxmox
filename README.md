### 레포지토리 구조

```
infra-proxmox/
├─ terraform/
│  ├─ haproxy/
│  └─ yml/
└─ cloud-init/
```

### Terraform 구성

- Terraform: `>= 1.15.3, < 1.16.0`
- `terraform/`: Kubernetes VM 생성
- `terraform/haproxy/`: VLAN20 DMZ On-Prem HAProxy VM과 keepalived VIP 생성

### On-Prem HAProxy

`terraform/haproxy`는 HAProxy VM을 VLAN20 DMZ에 생성하고 keepalived로 DMZ VIP를 제공한다. HAProxy backend는 VLAN40 Kubernetes Ingress VIP의 80/443만 바라보도록 구성한다.

```bash
cd terraform/haproxy
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

적용 전에 `terraform.tfvars`에서 다음 값을 실제 값으로 변경해야 한다.

- `haproxy_vip`: VLAN20 DMZ HAProxy VIP
- `ingress_vip`: VLAN40 Kubernetes Ingress VIP
- `keepalived_interface`: VM 내부 NIC 이름, 예: `eth0` 또는 `ens18`
- `keepalived_auth_pass`: 8자 이하 VRRP 인증 문자열
