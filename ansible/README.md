# Proxmox Kubernetes Ansible Guide

이 문서는 Proxmox VM 9대로 Kubernetes 클러스터를 처음부터 끝까지 구성하는 실행 가이드입니다.

현재 구성은 10G 내부망을 Kubernetes node network로 사용하지 않습니다. Ansible SSH, Kubernetes API VIP, kubelet node IP, control-plane advertise address, Calico node IP를 모두 관리망 `172.17.128.0/22` 기준으로 맞춥니다.

## 최종 목표

구성 완료 후 기대 상태는 다음과 같습니다.

| 역할 | 노드 | Kubernetes node IP |
| --- | --- | --- |
| control-plane | `cp1` | `172.17.128.193` |
| control-plane | `cp2` | `172.17.128.170` |
| control-plane | `cp3` | `172.17.128.194` |
| worker | `worker1` | `172.17.128.171` |
| worker | `worker2` | `172.17.128.189` |
| worker | `worker3` | `172.17.128.176` |
| worker | `worker4` | `172.17.128.172` |
| worker | `worker5` | `172.17.128.175` |
| worker | `worker6` | `172.17.128.190` |

Kubernetes API는 관리망 VIP로 접근합니다.

```text
https://172.17.128.30:6443
```

## 왜 10G 내부망이 아니라 관리망을 쓰는가

현재 작업 PC는 관리망 `172.17.128.0/22`에는 접근할 수 있지만, 10G VLAN에는 직접 접근할 수 없습니다. 이 조건에서는 Kubernetes의 기본 제어 경로를 관리망으로 맞추는 것이 맞습니다.

### 1. Ansible이 접근 가능한 네트워크여야 한다

Ansible은 작업 PC에서 각 VM으로 SSH 접속해서 설치와 설정을 진행합니다.

작업 PC에서 10G VLAN으로 접근할 수 없다면 `ansible_host`에 10G IP를 넣는 순간 Ansible 실행이 막힙니다. 따라서 `ansible_host`는 반드시 관리망 IP여야 합니다.

### 2. Kubernetes API VIP도 작업 PC에서 접근 가능해야 한다

클러스터 구성 후 `kubectl`, 검증 명령, 장애 확인은 API VIP로 접근합니다.

API VIP를 10G 내부망에 두면 작업 PC에서 `kubectl`로 API에 접근할 수 없습니다. 지금 구조에서는 API VIP `172.17.128.30`을 관리망에 두는 것이 맞습니다.

### 3. kubelet node IP와 apiserver advertise address가 섞이면 문제가 커진다

Kubernetes에서 노드 IP는 단순 표시값이 아닙니다. 다음 값들과 연결됩니다.

- kubelet `--node-ip`
- `kubeadm init --apiserver-advertise-address`
- control-plane join 시 advertise address
- apiserver 인증서 SAN
- Calico node IP autodetection

한쪽은 관리망, 한쪽은 10G로 섞이면 인증서, control-plane join, CNI 통신 문제를 디버깅해야 합니다. 현재는 모든 제어 경로를 관리망으로 통일합니다.

### 4. 10G는 나중에 목적별 트래픽에 쓰는 편이 안전하다

10G 네트워크 자체를 쓰지 말자는 뜻은 아닙니다. 다만 지금 클러스터 부트스트랩과 제어 경로에는 관리망을 쓰는 것이 단순하고 안정적입니다.

나중에 10G를 쓰려면 다음처럼 별도 목적에 맞춰 적용하는 편이 좋습니다.

- 스토리지 트래픽
- 백업 트래픽
- 애플리케이션 전용 통신
- 별도 라우팅과 접근 경로가 준비된 Kubernetes node network

10G를 Kubernetes node network로 쓰려면 작업 PC 또는 bastion이 10G VLAN에 접근 가능해야 하고, VIP, 인증서 SAN, kubelet, Calico, control-plane advertise address를 모두 10G 기준으로 다시 맞춰야 합니다.

## 네트워크 설정 기준

현재 Ansible 설정은 다음 파일에 들어 있습니다.

```bash
infra-proxmox/ansible/group_vars/all.yml
```

현재 값:

```yaml
vip_address: 172.17.128.30
vip_interface: eth0
vip_cidr: 22
node_interface: eth0
node_cidr: 172.17.128.0/22
pod_cidr: 172.20.0.0/16
```

각 값의 의미:

| 값 | 의미 |
| --- | --- |
| `vip_address` | Kubernetes API VIP |
| `vip_interface` | VIP를 붙일 NIC |
| `vip_cidr` | VIP CIDR prefix |
| `node_interface` | 각 노드의 관리망 IP가 붙은 NIC |
| `node_cidr` | Calico가 노드 IP를 고를 CIDR |
| `pod_cidr` | Kubernetes Pod 대역 |

`vip_address`는 관리망에서 사용하지 않는 IP여야 합니다. 다른 VM, 라우터, DHCP pool과 충돌하면 안 됩니다.

## 1. 로컬 준비

작업 PC에서 Ansible을 설치합니다. macOS 기준:

```bash
brew install ansible
```

설치 확인:

```bash
ansible --version
```

프로젝트의 Ansible 디렉터리로 이동합니다.

```bash
cd infra-proxmox/ansible
```

## 2. VM 준비 상태 확인

각 VM은 다음 조건을 만족해야 합니다.

- Ubuntu 22.04 계열
- `kosa` 사용자 존재
- `kosa` 사용자가 sudo 가능
- 작업 PC의 SSH key로 접속 가능
- 관리망 IP가 `eth0`에 설정되어 있음
- VM 시간이 크게 틀어져 있지 않음

현재 SSH key 설정은 `inventory.ini`에 있습니다.

```ini
[k8s:vars]
ansible_user=kosa
ansible_ssh_private_key_file=~/.ssh/id_team1_sunmin
ansible_python_interpreter=/usr/bin/python3.10
```

키 파일 권한도 확인합니다.

```bash
chmod 600 ~/.ssh/id_team1_sunmin
```

## 3. inventory.ini 확인

파일:

```bash
infra-proxmox/ansible/inventory.ini
```

현재 구조:

```ini
[control_plane]
cp1 ansible_host=172.17.128.193
cp2 ansible_host=172.17.128.170
cp3 ansible_host=172.17.128.194

[workers]
worker1 ansible_host=172.17.128.171
worker2 ansible_host=172.17.128.189
worker3 ansible_host=172.17.128.176
worker4 ansible_host=172.17.128.172
worker5 ansible_host=172.17.128.175
worker6 ansible_host=172.17.128.190
```

`ansible_host`는 Ansible SSH 접속 주소이며, 기본 Kubernetes node IP로도 사용합니다.
SSH 접속 주소와 Kubernetes node IP가 다를 때만 해당 호스트에 `node_ip`를 추가합니다.

현재는 관리망만 쓰므로 `ansible_host`만 관리하면 됩니다. DHCP로 VM IP가 바뀌면 `ansible_host`를 수정합니다.

inventory가 제대로 읽히는지 확인합니다.

```bash
ansible-inventory --host cp1
ansible-inventory --host worker1
```

출력에 `ansible_host`, `vip_address`, `node_cidr`가 보여야 합니다.

## 4. SSH와 sudo 확인

전체 노드 SSH 확인:

```bash
ansible k8s -m ping
```

전체 노드 sudo 확인:

```bash
ansible k8s -b -m command -a 'hostname'
```

각 노드의 관리망 IP가 `eth0`에 있는지 확인합니다.

```bash
ansible k8s -b -m command -a 'ip -4 addr show dev eth0'
```

여기서 각 노드의 `ansible_host` IP가 보여야 합니다.

## 5. 플레이북 문법 확인

실행 전에 문법을 확인합니다.

```bash
ansible-playbook --syntax-check playbook.yml
ansible-playbook --syntax-check playbook/initiallize.yml
```

둘 다 `playbook: ...`만 출력되고 에러가 없어야 합니다.

## 6. 기존 클러스터가 있으면 초기화

이미 Kubernetes를 한 번 만든 VM이라면 먼저 초기화합니다.

주의: 이 작업은 기존 Kubernetes 클러스터를 삭제합니다. etcd 데이터, kubeconfig, CNI 상태, containerd 상태도 지웁니다.

```bash
ansible-playbook playbook/initiallize.yml
```

초기화를 실행해야 하는 경우:

- 이전에 10G `10.10.10.x` node IP로 클러스터를 만들었음
- kubeadm join이 실패한 상태가 남아 있음
- CNI나 kubelet 상태가 꼬여 있음
- 같은 VM으로 클러스터를 새로 만들고 싶음

깨끗한 새 VM이라면 이 단계는 생략할 수 있습니다.

## 7. 클러스터 생성

전체 플레이북을 실행합니다.

```bash
ansible-playbook playbook.yml
```

`playbook.yml`은 다음 순서로 실행됩니다.

1. `00_cp1-init.yml`: 전체 노드 hostname 설정
2. `01_pre.yml`: apt/dpkg 사전 정리
3. `02_00_setup.yml`: containerd, kubelet, kubeadm, kubectl 설치
4. `02_01_kube-vip.yml`: kube-vip manifest 생성, cp1 kubeadm init
5. `03_init.yml`: kubeconfig 설정, kube-vip 권한 부여, Calico manifest 렌더링/설치, join command 생성
6. `04_0_cp-join.yml`: cp2, cp3 control-plane join
7. `04_1_worker-join.yml`: worker join
8. `05_post.yml`: 후처리

control-plane join은 `serial: 1`로 한 대씩 진행됩니다. etcd member join 안정성을 위해 동시에 join하지 않습니다.

## 8. 정상 상태 확인

노드 상태 확인:

```bash
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide'
```

정상 기준:

- 모든 노드가 `Ready`
- `INTERNAL-IP`가 `172.17.128.x`
- `10.10.10.x`가 보이면 현재 문서 기준으로는 잘못된 상태

kube-system pod 확인:

```bash
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system -o wide'
```

정상 기준:

- `calico-node`가 모든 노드에서 `1/1 Running`
- `kube-apiserver`, `etcd`, `kube-controller-manager`, `kube-scheduler`가 control-plane에서 Running
- `coredns`가 Running

API VIP 확인:

```bash
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf --server=https://172.17.128.30:6443 cluster-info'
```

정상 출력 예시:

```text
Kubernetes control plane is running at https://172.17.128.30:6443
```

kubeconfig가 VIP를 바라보는지 확인:

```bash
ansible cp1 -b -m command -a 'grep server /etc/kubernetes/admin.conf'
```

정상 값:

```text
server: https://172.17.128.30:6443
```

Calico node IP autodetection 확인:

```bash
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system get daemonset calico-node -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name==\"IP_AUTODETECTION_METHOD\")].value}{\"\\n\"}"'
```

정상 값:

```text
cidr=172.17.128.0/22
```

## 9. VIP owner 확인

VIP owner는 실제로 `172.17.128.30`을 들고 있는 control-plane입니다.

```bash
ansible kube_vip -b -m shell -a 'hostname; ip -br addr show eth0 | grep 172.17.128.30 || true'
```

Lease로도 확인합니다.

```bash
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf get lease plndr-cp-lock -n kube-system -o wide'
```

`HOLDER` 값이 현재 kube-vip leader입니다.

## 10. etcd 상태 확인

cp1의 etcd 컨테이너 ID를 확인합니다.

```bash
ansible cp1 -b -m command -a 'crictl ps --name etcd -q'
```

컨테이너 ID를 사용해 etcd health를 확인합니다.

```bash
ansible cp1 -b -m shell -a 'id=$(crictl ps --name etcd -q | head -n1); crictl exec "$id" etcdctl --endpoints=https://172.17.128.193:2379,https://172.17.128.170:2379,https://172.17.128.194:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key endpoint health -w table'
```

정상 기준은 세 endpoint가 모두 `HEALTH=true`입니다.

## 11. VIP failover 테스트

현재 VIP owner를 확인합니다.

```bash
ansible kube_vip -b -m shell -a 'hostname; ip -br addr show eth0 | grep 172.17.128.30 || true'
```

예를 들어 현재 owner가 `cp2`라면 cp2에서 kubelet과 kube-vip 컨테이너를 중지합니다.

```bash
ansible cp2 -b -m shell -a 'systemctl stop kubelet; crictl ps --name kube-vip -q | xargs -r crictl stop'
```

몇 초 뒤 VIP가 다른 control-plane으로 이동했는지 확인합니다.

```bash
ansible kube_vip -b -m shell -a 'hostname; ip -br addr show eth0 | grep 172.17.128.30 || true'
```

API가 계속 응답하는지도 확인합니다.

```bash
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf --server=https://172.17.128.30:6443 get nodes'
```

테스트가 끝나면 중지한 노드의 kubelet을 다시 올립니다.

```bash
ansible cp2 -b -m systemd -a 'name=kubelet state=started enabled=yes'
```

## 자주 보는 문제

### SSH가 안 된다

`inventory.ini`의 `ansible_host`가 현재 작업 PC에서 접근 가능한 관리망 IP인지 확인합니다.

```bash
ansible k8s -m ping
```

특정 노드만 실패하면 그 노드의 DHCP IP, SSH key, VM 전원 상태를 먼저 봅니다.

### sudo가 안 된다

아래 명령으로 실패 노드를 확인합니다.

```bash
ansible k8s -b -m command -a 'whoami'
```

정상 출력은 `root`입니다.

### node IP가 10.10.10.x로 잡힌다

현재 구성에서는 잘못된 상태입니다. 확인 명령:

```bash
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide'
```

이미 10G 기준으로 만들어진 클러스터라면 초기화 후 다시 생성합니다.

```bash
ansible-playbook playbook/initiallize.yml
ansible-playbook playbook.yml
```

### VIP가 아무 노드에도 없다

kube-vip 상태와 로그를 봅니다.

```bash
ansible kube_vip -b -m shell -a 'crictl ps --name kube-vip; crictl logs $(crictl ps --name kube-vip -q | head -n1) 2>/dev/null | tail -n 50'
```

주로 보는 원인:

- kube-vip pod가 실행되지 않음
- `/etc/kubernetes/admin.conf`가 없음
- kube-vip가 Lease를 읽을 권한이 없음
- VIP가 다른 장비와 IP 충돌
- `vip_interface`가 실제 NIC 이름과 다름

### control-plane join이 실패한다

control-plane join 실패는 이전 실패 상태가 남았거나 etcd learner promotion 타이밍 문제인 경우가 많습니다.

현재 플레이북은 cp2, cp3를 `serial: 1`로 한 대씩 join합니다. 그래도 실패했다면 초기화 후 다시 실행하는 편이 가장 빠릅니다.

```bash
ansible-playbook playbook/initiallize.yml
ansible-playbook playbook.yml
```

### Calico가 Running이 아니다

Calico pod 상태를 봅니다.

```bash
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system -l k8s-app=calico-node -o wide'
```

Calico 설정값을 확인합니다.

```bash
ansible cp1 -b -m command -a 'kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system get daemonset calico-node -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name==\"IP_AUTODETECTION_METHOD\")].value}{\"\\n\"}"'
```

정상 값은 `cidr=172.17.128.0/22`입니다.

## 커밋 전 주의

`inventory.ini`는 로컬 IP와 SSH key 경로가 들어 있어 `.gitignore` 대상입니다.

`admin.conf` 같은 kubeconfig는 인증 정보가 들어갑니다. 현재 플레이북은 worker 배포 시 메모리에서 전달하고 로컬 파일로 저장하지 않습니다.
