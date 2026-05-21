# Proxmox Kubernetes Ansible

Proxmox VM 위에 kubeadm 기반 Kubernetes 클러스터를 구성하기 위한 Ansible 실행 디렉터리입니다.

구성 목표는 다음과 같습니다.

- control-plane 3대, worker 6대 구성
- kube-vip 기반 Kubernetes API VIP 구성
- Calico CNI 설치
- 관리망과 10G node network 분리

## 네트워크 모델

| 용도 | 네트워크 | 설명 |
| --- | --- | --- |
| Ansible SSH | 관리망 `172.17.128.0/22` | 작업 PC 또는 Ansible VM이 접속하는 주소 |
| Kubernetes API VIP | 관리망 `172.17.130.10` | 외부 `kubectl` 접근용 API endpoint |
| Kubernetes node IP | 10G망 `10.10.10.0/24` | kubelet node IP, control-plane advertise, Calico node IP |
| Pod CIDR | `10.244.0.0/16` | Kubernetes Pod 대역 |

API VIP는 관리망에 있고, 노드 간 Kubernetes/Calico 통신은 `node_ip`로 지정한 10G망을 사용합니다.

## 주요 파일

| 파일 | 역할 |
| --- | --- |
| `inventory.ini` | 실제 VM 접속 주소와 Kubernetes node IP 정의 |
| `inventory.ini.example` | inventory 작성 예시 |
| `group_vars/all.yml` | VIP, NIC, CIDR, Kubernetes 버전 등 공통 변수 |
| `playbook.yml` | 클러스터 구성 진입점 |
| `playbook/initialize.yml` | 기존 클러스터 상태 초기화 (패키지 유지) |
| `playbook/reset.yml` | 클러스터 완전 초기화 (패키지 포함 제거) |
| `playbook/reset-kube-vip.yml` | control-plane만 초기화 |
| `playbook/05_post_join_kube_vip.yml` | control-plane join 이후 kube-vip static pod manifest 설치/복구 |
| `playbook/07_install_helm.yml` | cp1 노드에 Helm CLI 설치 |

`inventory.ini`는 SSH key 경로와 실제 IP가 들어가므로 git에 포함하지 않습니다.
`admin.conf` 같은 kubeconfig는 클러스터 관리자 인증 정보이므로 git에 포함하지 않습니다.
worker에는 `admin.conf` 대신 읽기 전용 kubeconfig를 배포합니다.

## 사전 조건

- VM OS: Ubuntu 22.04 계열
- `kosa` 사용자와 sudo 권한
- 작업 PC 또는 Ansible VM에서 관리망 IP로 SSH 가능
- 관리망 IP는 `eth0`, 10G node IP는 `eth1`에 설정
- 모든 노드의 10G node IP가 서로 통신 가능
- 작업 PC 또는 Ansible VM에 Ansible 설치

```bash
brew install ansible
```

## Inventory 작성

`inventory.ini.example`을 복사해 `inventory.ini`를 작성합니다.

```ini
[control_plane]
cp1 ansible_host=172.17.128.21 node_ip=10.10.10.51
cp2 ansible_host=172.17.128.22 node_ip=10.10.10.52
cp3 ansible_host=172.17.128.23 node_ip=10.10.10.53

[workers]
worker1 ansible_host=172.17.128.24 node_ip=10.10.10.54
```

`ansible_host`는 SSH 접속 주소이고, `node_ip`는 Kubernetes가 사용할 10G 주소입니다.
실제 VM의 `eth1` 주소와 `node_ip`가 다르면 playbook이 중단됩니다.

## 실행 전 확인

```bash
cd infra-proxmox/ansible
ansible-inventory --host cp1
ansible k8s -m ping
ansible k8s -b -m command -a 'ip -br -4 addr'
ansible-playbook --syntax-check playbook.yml
ansible-playbook --syntax-check playbook/initialize.yml
```

`cp1`의 `node_ip`, `vip_address`, `node_interface` 값이 의도와 맞는지 확인합니다.

## 초기화

기존 Kubernetes 상태가 남아 있으면 먼저 초기화합니다.

```bash
ansible-playbook playbook/initialize.yml
```

새 VM이면 생략할 수 있습니다.

## 클러스터 생성

```bash
ansible-playbook playbook.yml
```

실행 흐름은 다음 순서입니다.

1. hostname 및 `/etc/hosts` 설정 (전체 노드)
2. apt 사전 작업 (전체 노드)
3. containerd, kubelet, kubeadm, kubectl 설치 (전체 노드) + kubectl/kubeadm bash 자동완성 (control-plane)
4. kube-vip manifest 사전 생성 및 cp1 kubeadm init
5. cp2, cp3 control-plane join → worker join
6. control-plane 전체에 kube-vip manifest 설치/복구 (join 이후)
7. Calico CNI 설치
8. Helm CLI 설치 (cp1)

## 완료 후 확인

```bash
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide'
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system get pods -o wide'
ansible workers -b --become-user kosa -m command -a 'kubectl get nodes'
ansible kube_vip -b -m shell -a 'hostname; ip -br addr show eth0 | grep 172.17.130.10 || true'
ansible cp1 -b -m command -a 'helm version --short'
```

정상 기준은 다음과 같습니다.

- 모든 노드가 `Ready`
- 노드 `INTERNAL-IP`가 `10.10.10.x`
- `calico-node`, `kube-vip`, control-plane Pod가 `Running`
- worker의 `kubectl get nodes`가 조회 전용 kubeconfig로 동작
- control-plane 중 한 대가 `172.17.130.10` VIP를 보유
- cp1에서 `helm version --short`가 정상 출력

## 운영 메모

- `node_ip`를 바꾸면 기존 클러스터와 인증서가 꼬일 수 있으므로 초기화 후 다시 구성합니다.
- 10G NIC 이름이 `eth1`이 아니면 `group_vars/all.yml`의 `node_interface`를 수정합니다.
- Kubernetes 버전 변경은 `group_vars/all.yml`의 `kube_version`만 수정합니다. APT 저장소 URL도 자동으로 반영됩니다.
- VIP는 외부 API 접근용이고, Calico는 클러스터 내부 Kubernetes service endpoint를 사용합니다.
- worker kubeconfig는 조회 전용입니다. 리소스 생성, 수정, 삭제는 control-plane의 관리자 kubeconfig로 수행합니다.
- playbook은 반복 실행 가능하도록 구성했지만, 클러스터 구조를 바꾸는 변경은 초기화 후 재실행하는 편이 단순합니다.

## kube-vip 장애 확인 / 복구

VIP는 control-plane 중 한 대의 `vip_interface`에만 붙어야 합니다.

```bash
ansible kube_vip -b -m shell -a 'hostname; ip -br addr show eth0 | grep -F "172.17.130.10/32" || true'
ansible kube_vip -b -m shell -a 'hostname; crictl ps -a --name kube-vip'
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf --server=https://172.17.130.10:6443 --request-timeout=10s get --raw=/readyz'
```

cp1 장애 중에 VIP가 cp2/cp3로 넘어오지 않으면, 살아있는 control-plane에 kube-vip manifest가 있는지 확인합니다.

```bash
ansible 'cp2:cp3' -b -m shell -a 'hostname; ls -l /etc/kubernetes/manifests/kube-vip.yaml 2>/dev/null || true; crictl ps -a --name kube-vip'
```

누락되어 있으면 살아있는 control-plane만 대상으로 복구합니다.

```bash
ansible-playbook playbook/05_post_join_kube_vip.yml --limit 'cp2:cp3'
```
