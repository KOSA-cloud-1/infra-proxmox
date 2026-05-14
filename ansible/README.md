# Proxmox Kubernetes Ansible

이 디렉터리는 Proxmox VM 위에 Kubernetes 클러스터를 구성하기 위한 Ansible 실행 단위입니다.

목표는 다음과 같습니다.

- control-plane 3대와 worker 6대 구성
- kubeadm 기반 Kubernetes 설치
- kube-vip 기반 Kubernetes API VIP 구성
- Calico CNI 설치
- 관리망과 10G node network 분리

## 네트워크 모델

현재 구성은 하이브리드 구조입니다.

| 용도 | 네트워크 | 설명 |
| --- | --- | --- |
| Ansible SSH | 관리망 `172.17.128.0/22` | 작업 PC 또는 Ansible 실행 VM이 접속하는 주소 |
| Kubernetes API VIP | 관리망 `172.17.128.30` | 작업 PC에서 `kubectl`로 접근 가능한 API endpoint |
| Kubernetes node IP | 10G망 `10.10.10.0/24` | kubelet, control-plane advertise, Calico node IP |
| Pod CIDR | `172.20.0.0/16` | Kubernetes Pod 대역 |

이 방식은 작업 PC가 10G망에 직접 접근하지 못해도 Kubernetes API는 관리망 VIP로 접근할 수 있고, 클러스터 내부 노드 통신은 10G망을 사용합니다.

10G node network를 쓰는 것은 괜찮은 구성입니다. 다만 각 VM의 10G NIC와 IP가 안정적으로 설정되어 있어야 하고, 10G망 장애는 Kubernetes 내부 통신 장애로 이어질 수 있습니다. 단순함이 더 중요하면 관리망만 쓰는 구성이 낫고, 노드 간 트래픽 성능이 중요하면 현재 구성이 더 적합합니다.

## 주요 파일

| 파일 | 역할 |
| --- | --- |
| `inventory.ini` | 실제 실행 대상 VM, SSH 주소, Kubernetes node IP 정의 |
| `inventory.ini.example` | inventory 작성 예시 |
| `group_vars/all.yml` | VIP, NIC, CIDR 등 공통 네트워크 변수 |
| `playbook.yml` | 전체 클러스터 구성 진입점 |
| `playbook/initiallize.yml` | 기존 클러스터 상태 초기화 |

`inventory.ini`는 로컬 환경 값과 SSH key 경로가 들어가므로 git에 포함하지 않습니다. `admin.conf` 같은 kubeconfig는 인증 정보가 들어가므로 worker 노드나 git 저장소에 배포하지 않습니다.

## 사전 조건

각 VM은 다음 조건을 만족해야 합니다.

- Ubuntu 22.04 계열
- `kosa` 사용자 존재
- `kosa` 사용자가 sudo 가능
- 작업 PC 또는 Ansible 실행 VM에서 관리망 IP로 SSH 가능
- 관리망 IP가 `eth0`에 설정되어 있음
- 10G node IP가 `eth1`에 설정되어 있음
- VM 시간이 크게 틀어져 있지 않음

작업 PC에는 Ansible이 필요합니다.

```bash
brew install ansible
```

## Inventory 작성

`inventory.ini.example`을 참고해 `inventory.ini`를 작성합니다.

```ini
[control_plane]
cp1 ansible_host=172.17.128.21 node_ip=10.10.10.21

[workers]
worker1 ansible_host=172.17.128.24 node_ip=10.10.10.24
```

`ansible_host`는 Ansible SSH 접속 주소입니다.
`node_ip`는 Kubernetes가 노드 IP로 사용할 10G 주소입니다.

관리망 IP가 바뀌면 `ansible_host`를 수정하고, 10G IP가 바뀌면 `node_ip`를 수정합니다.

## 실행 전 확인

Ansible 디렉터리로 이동합니다.

```bash
cd infra-proxmox/ansible
```

inventory가 의도대로 읽히는지 확인합니다.

```bash
ansible-inventory --host cp1
```

전체 노드 SSH와 sudo를 확인합니다.

```bash
ansible k8s -m ping
ansible k8s -b -m command -a 'hostname'
```

관리망과 10G망 IP가 각 NIC에 있는지 확인합니다.

```bash
ansible k8s -b -m command -a 'ip -4 addr show dev eth0'
ansible k8s -b -m command -a 'ip -4 addr show dev eth1'
```

플레이북 문법을 확인합니다.

```bash
ansible-playbook --syntax-check playbook.yml
ansible-playbook --syntax-check playbook/initiallize.yml
```

## 클러스터 초기화

기존 Kubernetes 상태가 남아 있으면 먼저 초기화합니다.

```bash
ansible-playbook playbook/initiallize.yml
```

초기화는 기존 Kubernetes 클러스터 상태, kubeconfig, CNI 상태, containerd 상태를 제거합니다. 새 VM이면 생략할 수 있습니다.

## 클러스터 생성

전체 구성을 실행합니다.

```bash
ansible-playbook playbook.yml
```

실행 순서는 다음 흐름입니다.

1. VM hostname과 사전 상태 정리
2. containerd, kubelet, kubeadm, kubectl 설치
3. kube-vip manifest 생성과 cp1 초기화
4. kubeconfig 설정, kube-vip 권한 부여, Calico 설치
5. 추가 control-plane과 worker join

## 완료 후 확인

노드 상태를 확인합니다.

```bash
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide'
```

정상 기준:

- 모든 노드가 `Ready`
- `INTERNAL-IP`가 `10.10.10.x`
- API endpoint가 `https://172.17.128.30:6443`

Calico 설정도 10G node network를 바라봐야 합니다.

```bash
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system get daemonset calico-node -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name==\"IP_AUTODETECTION_METHOD\")].value}{\"\\n\"}"'
```

정상 값:

```text
cidr=10.10.10.0/24
```

VIP owner는 다음 명령으로 확인합니다.

```bash
ansible kube_vip -b -m shell -a 'hostname; ip -br addr show eth0 | grep 172.17.128.30 || true'
```

## 운영 메모

- 작업 PC에서 API 접근이 필요하면 VIP는 관리망에 유지합니다.
- Kubernetes node IP를 10G로 쓰려면 모든 노드의 `node_ip`가 서로 통신 가능해야 합니다.
- 10G NIC 이름이 `eth1`이 아니면 `group_vars/all.yml`의 `node_interface`를 수정합니다.
- 이미 다른 node IP 기준으로 클러스터를 만들었다면 `initiallize.yml`로 초기화한 뒤 다시 구성하는 편이 가장 빠릅니다.
- `admin.conf` 같은 kubeconfig는 인증 정보가 들어가므로 git에 포함하지 않습니다.
