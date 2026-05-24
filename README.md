# infra-proxmox

Proxmox 위에 Kubernetes VM, On-Prem HAProxy, kubeadm 기반 Kubernetes 클러스터를 구성하기 위한 인프라 코드 저장소입니다.

## 구성

```text
infra-proxmox/
├─ terraform/
│  ├─ k8s-vm/       # Kubernetes control-plane / worker VM 생성
│  └─ haproxy/      # DMZ HAProxy VM, keepalived VIP 생성
└─ ansible/         # kubeadm Kubernetes 클러스터 구성
```

## 사전 조건

- Terraform `>= 1.15.3, < 1.16.0`
- Proxmox provider `bpg/proxmox` `0.106.0`
- Proxmox API token
- Proxmox 노드 SSH 접속 권한
- VM clone에 사용할 cloud-init template
- Ansible 실행 환경

`terraform.tfvars`, `inventory.ini`, Terraform state, kubeconfig 등 실제 인증 정보가 들어가는 파일은 git에 포함하지 않습니다.

## 실행 순서

### 1. Kubernetes VM 생성

```bash
cd terraform/k8s-vm
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

또는 단계별 배포 스크립트를 사용할 수 있습니다.

```bash
cd terraform/k8s-vm
./terraform-execute.sh
```

`terraform.tfvars`에는 Proxmox API 정보, template VM ID, SSH 공개키, control-plane/worker VM ID와 IP를 설정합니다.

### 2. Kubernetes 클러스터 구성

```bash
cd ansible
cp inventory.ini.example inventory.ini
ansible k8s -m ping
ansible-playbook --syntax-check playbook.yml
ansible-playbook playbook.yml
```

Ansible은 다음 작업을 수행합니다.

1. hostname, `/etc/hosts`, 공통 패키지 설정
2. containerd, kubelet, kubeadm, kubectl 설치
3. kube-vip 기반 Kubernetes API VIP 구성 (cp1 init → cp2,cp3 join 후 적용)
4. control-plane / worker join
5. Calico CNI 설치
6. Helm CLI 설치 및 kubectl/kubeadm bash 자동완성 설정

자세한 내용은 `ansible/README.md`를 참고합니다.

### 3. On-Prem HAProxy 생성

```bash
cd terraform/haproxy
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

또는 단계별 배포 스크립트를 사용할 수 있습니다.

```bash
cd terraform/haproxy
./terraform-execute.sh
```

`terraform/haproxy`는 VLAN20 DMZ에 HAProxy VM 2대를 생성하고, **keepalived VRRP로 단일 DMZ VIP를 active/backup 이중화**합니다(우선순위 `haproxy-1`=110 MASTER / `haproxy-2`=100 BACKUP, MASTER만 VIP 보유). HAProxy는 VIP의 `80` 트래픽을 Kubernetes Ingress VIP의 `80`으로 TCP 전달합니다.

> TLS(443)는 상위 **AWS NLB에서 종료**되므로 온프렘 HAProxy는 평문 HTTP `80`만 처리합니다(443 frontend 없음). 전체 외부 흐름은 `infra-aws` README의 트래픽 흐름 다이어그램을 참고하세요.

주요 변수는 다음과 같습니다.

| 변수 | 설명 |
| --- | --- |
| `haproxy_vip` | VLAN20 DMZ에서 keepalived가 제공할 HAProxy VIP |
| `ingress_vip` | Kubernetes Ingress Controller 또는 MetalLB가 제공하는 backend VIP |
| `haproxy_instances` | HAProxy VM ID, Proxmox 노드, DMZ IP, 리소스, keepalived priority |
| `keepalived_interface` | VIP를 올릴 VM 내부 NIC 이름. 현재 템플릿 기준 `eth0` |
| `keepalived_auth_pass` | VRRP 인증 비밀번호. keepalived 제한에 맞춰 8자 이하 |

cloud-init은 HAProxy VM에 `haproxy`, `keepalived`, `qemu-guest-agent`를 설치하고, HAProxy 설정과 keepalived 설정을 자동으로 배포합니다.

## 네트워크 요약

| 영역 | 대역 / 값 | 용도 |
| --- | --- | --- |
| Proxmox node network | `192.168.36.0/24` | Proxmox API 및 노드 SSH |
| 관리망 | `172.17.128.0/22` | Ansible SSH, Kubernetes API VIP |
| Kubernetes node network | `10.10.10.0/24` | kubelet node IP, control-plane advertise, Calico node IP |
| DMZ | `172.17.32.0/24` | On-Prem HAProxy VM IP와 HAProxy VIP |

## 검증 명령

Terraform:

```bash
terraform -chdir=terraform/k8s-vm fmt -check
terraform -chdir=terraform/k8s-vm validate
terraform -chdir=terraform/haproxy fmt -check
terraform -chdir=terraform/haproxy validate
```

Ansible:

```bash
cd ansible
ansible-inventory --graph
ansible k8s -m ping
ansible-playbook --syntax-check playbook.yml
```

Kubernetes:

```bash
cd ansible
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide'
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf get svc -A -o wide'
```

HAProxy 배포 후:

```bash
ssh <haproxy-vm>
systemctl status qemu-guest-agent haproxy keepalived
haproxy -c -f /etc/haproxy/haproxy.cfg
ip -br addr
```
