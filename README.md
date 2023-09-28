# K8s Standup on Rocky 8.7

## Important
This documentation assumes you've navigated to this directory in your file tree (`cat README.md` returns this doc).

Run commands on all nodes unless prefixed with "[CP]" - these should run on a _single_ control-plane node.

## Design Goals
The goal of this project is to bootstrap a high-availability Kubernetes multi-node and GlusterFS cluster in a challenging environment: bare metal, heterogenous nodes, rootless containers as a critical first step to meeting NSA/CISA guidance for hardened Kubernetes. The project uses declarative provisioning for all resources; nothing was typed in a terminal except what is provided in this README or provisioned using the subfolders.

---
# Bare Metal Preparation
## Configure a Static Route
To enforce network sequestration, the chosen networking plugins operate entirely within L2. For this cluster to be routable externally, we opted to configure a static route from our top-of-rack router.
```md
Static Route: K8s
Destination Network: 10.0.10.0/24
Distance: 1
Static Route Type: Interface
Interface: Trusted LAN
```

## [ALL] Set Preferred Kubernetes Version
```sh
# e.g. for 1.24.8 from yum list --showduplicates kubeadm --disableexcludes=kubernetes
export VERSION=1.26
export PATCHVERSION=1
```

## [ALL] /etc/hosts
The DNS entry for k8s-control-plane-lb must resolve to either a single control-plane node (shown here) or to a load balancer for control-plane nodes.
```conf
10.0.8.254 node1 tengig1 k8s-control-plane-lb
10.0.8.253 node2 tengig2
10.0.8.252 node3 tengig3
10.0.8.251 node4 tengig4
```

## [ALL] /etc/modules-load.d/k8s.conf
```conf
overlay
br_netfilter
```

## [ALL] /etc/sysctl.d/k8s.conf
```ini
net.bridge.bridge-nf-call-iptables  = 1         # default 0
net.ipv4.ip_forward                 = 1         # default 0
net.bridge.bridge-nf-call-ip6tables = 1         # default 0
net.core.somaxconn                  = 10000     # default 4096
```

## [ALL] Disable THP
Necessary for redis, which is used in our authentication app deployment. If you're standing up a non-redis cluster and won't be deploying any of the apps provided in the subfolders, you can skip this.
```sh
sudo grub2-editenv - set "$(sudo grub2-editenv - list | grep kernelopts) transparent_hugepage=never"
```

## [ALL] /etc/yum.repos.d/kubernetes.repo
```ini
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
```

## [ALL] /etc/NetworkManager/conf.d/calico.conf
```bash
[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali
```

## [ALL] Setup Prerequisites
```sh
sudo dnf update -y
sudo dnf install -y iproute-tc chrony yum-utils yum-plugin-versionlock git
sudo systemctl enable --now chronyd

sudo swapoff -a
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
sudo setenforce 0

sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=2379-2380/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=10251/tcp
sudo firewall-cmd --permanent --add-port=10252/tcp
sudo firewall-cmd --permanent --add-port=30000-32767/tcp
sudo firewall-cmd --reload

sudo modprobe overlay
sudo modprobe br_netfilter
sudo sysctl --system
```

## [ALL] /etc/crio/crio.conf

Note: default capabilities should be significantly reduced from this configuration.

```toml
[crio]
[crio.api]
[crio.runtime]
selinux = false

default_capabilities = [
        "NET_RAW",
        "CHOWN",
        "DAC_OVERRIDE",
        "FSETID",
        "FOWNER",
        "SETGID",
        "SETUID",
        "SETPCAP",
        "NET_BIND_SERVICE",
        "KILL",
]
[crio.image]
[crio.network]
plugin_dirs = [
        "/opt/cni/bin",
        "/usr/libexec/cni",
]
[crio.metrics]
enable_metrics = true
metrics_port = 9537

[crio.tracing]
[crio.stats]
```


## [ALL] Install CRI-O
CRI-O is the RHEL-supported container engine, as it powers OpenShift. It's designed to play nice with rootless containers.
```sh
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_8/devel:kubic:libcontainers:stable.repo

sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/CentOS_8/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo

sudo dnf install -y crio
sudo systemctl enable --now crio
```

## [ALL] Install Kubernetes / Helm
```sh
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

sudo dnf install -y kubelet-$VERSION.$PATCHVERSION kubeadm-$VERSION.$PATCHVERSION kubectl-$VERSION.$PATCHVERSION --disableexcludes=kubernetes
sudo yum versionlock kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

export VERSION=;export PATCHVERSION=
```

>## PASS/FAIL: Infrastructure
>
>Ensure connection between all nodes, plus a connection between the router and nodes. 
> - `ping node1`
>
>Ensure kubectl version matches expected 
> - `kubectl version --short`
>
>Ensure kubeadm version matches expected 
> - `kubeadm version`

## [CP] Bootstrap Cluster
```sh
sudo mkdir -p /etc/kubernetes/config
sudo cp config.mount/* /etc/kubernetes/config/
sudo sed -i "s|REPLACEME|$(head -c 32 /dev/urandom | base64)|g" /etc/kubernetes/config/secret-encryption.yaml
sudo chmod 600 /etc/kubernetes/config/secret-encryption.yaml
sudo chown root:root /etc/kubernetes/config/secret-encryption.yaml

sudo kubeadm init --config infrastructure/cluster-config.yaml

```

## [CP] Perform Security Check
```sh
stat -c %a /etc/kubernetes/manifests/kube-apiserver.yaml # 644 or better
stat -c %a /etc/kubernetes/manifests/kube-controller-manager.yaml # 644 or better
stat -c %a /etc/kubernetes/manifests/kube-scheduler.yaml # 644 or better
stat -c %a /etc/kubernetes/manifests/etcd.yaml # 644 or better
stat -c %a /etc/kubernetes/admin.conf # 644 or better
stat -c %a /etc/kubernetes/scheduler.conf # 644 or better
stat -c %a /etc/kubernetes/controller-manager.conf # 644 or better
ls -laR /etc/kubernetes/pki/*.crt # 644 or better
stat -c %a /etc/systemd/system/kubelet.service.d/10-kubeadm.conf # 644 or better
stat -c %a /etc/kubernetes/kubelet.conf # 644 or better

ls -laR /etc/kubernetes/pki/*.key # 600 or better

stat -c %a /var/lib/etcd # 700 or better
stat -c %U:%G /etc/kubernetes/manifests/kube-apiserver.yaml # root:root
stat -c %U:%G /etc/kubernetes/manifests/kube-controller-manager.yaml # root:root
stat -c %U:%G /etc/kubernetes/manifests/kube-scheduler.yaml # root:root
stat -c %U:%G /etc/kubernetes/manifests/etcd.yaml # root:root
stat -c %U:%G /etc/kubernetes/admin.conf # root:root
stat -c %U:%G /etc/kubernetes/scheduler.conf # root:root
stat -c %U:%G /etc/kubernetes/controller-manager.conf # root:root
ls -laR /etc/kubernetes/pki/ # root:root
stat -c %U:%G /etc/kubernetes/kubelet.conf # root:root
stat -c %U:%G /etc/systemd/system/kubelet.service.d/10-kubeadm.conf # root:root

stat -c %U:%G /var/lib/etcd # etcd:etcd

# TODO:
# kubeconfig
# certificate auth
# https://cloud.redhat.com/blog/guide-to-kubernetes-ingress-network-policies
# https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#imagepolicywebhook
# https://media.defense.gov/2021/Aug/03/2002820425/-1/-1/0/CTR_Kubernetes_Hardening_Guidance_1.1_20220315.PDF
```

## [ALL] Set up Kube user
```sh
sudo useradd -m kube
sudo usermod -aG wheel kube
sudo mkdir -p /home/kube/.kube
```

## [CP] Copy Kube Config
```sh
sudo rsync -aP /etc/kubernetes/admin.conf node1:/home/kube/.kube/config
sudo rsync -aP /etc/kubernetes/admin.conf node2:/home/kube/.kube/config
sudo rsync -aP /etc/kubernetes/admin.conf node4:/home/kube/.kube/config

```

## [ALL] Configure permissions
```sh
sudo chown -R kube:kube /home/kube/.kube
sudo chmod 600 /home/kube/.kube/config
```
## [ALL] Reboot Nodes
Now's a good time for a reboot. I'm not sure if it's necessary, but 'reboot early and often' is a good rule of thumb when you're about to start debugging networking configs.
```sh
sudo reboot
```

## [CP] Setup Calico CNI
```sh
kubectl create namespace tigera-operator

helm repo add projectcalico https://projectcalico.docs.tigera.io/charts
helm install calico projectcalico/tigera-operator --version v3.25.1 -f infrastructure/networking/tigera-values.yaml --namespace tigera-operator
```


## [ALL] Join Other Nodes
```sh
sudo $(kubeadm token create  --print-join-command)
```

>## PASS/FAIL: Networking
>
>Confirm that all pods are running: 
> - `watch kubectl get pods -n calico-system`
>
>Confirm that pods can talk to each other:
> - `kubectl create deployment pingtest --image=busybox --replicas=3 -- sleep infinity`
> - `kubectl get pods --selector=app=pingtest --output=wide`
> - `kubectl exec -ti pingtest-xxxxxxx -- sh`
>
> Test ping and routing to the other pods and nodes
> - `ping 10.0.8.254 -c 4`
> - `ping 8.8.8.8 -c 4`
> - `ping 10.x.x.x -c 4`
> - `ip route get 10.x.x.x`
> 
> Clean up tests
> - `kubectl delete deployments.apps pingtest`

# App Deployment Bootstrap

## Configure MetalLB
Provides load balancing service between bare-metal nodes.
```sh
kubectl create ns metallb
kubectl config set-context --current --namespace=metallb
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb
kubectl apply -f infrastructure/networking/metallb-resources.yaml
```

> ## PASS/FAIL: LoadBalancer External IP
> Install nginx with an external IP
> - `kubectl apply -f infrastructure/test-nginx.yaml`
> - `watch kubectl get svc -n default`

## Configure Traefik
Provides reverse proxy into cluster. Note: requires _init/00-bootstrap.yaml and _init/10-storage.yaml
```sh
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=9000/tcp
sudo firewall-cmd --reload

kubectl create ns traefik
kubectl config set-context --current --namespace=traefik

kubectl create secret generic aws-credentials --from-literal=AWS_ACCESS_KEY_ID=XXXXX --from-literal=AWS_SECRET_ACCESS_KEY=XXXXX

helm repo add traefik https://helm.traefik.io/traefik
helm install traefik traefik/traefik -f infrastructure/networking/traefik-values.yaml
```

## Consider Installing Bootstraps Provided in _init Subfolder
These are highly workflow-dependent, but this is what I use.
- __Namespaces__: we don't want to provision these from inside a yaml file that we'd later accidentally `kubectl delete`, so I do them all at once here.
- __Storage__: I'd have preferred to run Ceph, but since I'm hosting the storage cluster on the same bare metal machines as k8s, the container runtime requirements can and will conflict. You'll end up with a dead K8s or a dead Ceph sooner or later. [Gluster Installation Instructions](https://docs.rockylinux.org/guides/file_sharing/glusterfs/).
- __Authentication__: I selected Authelia as a universal authentication layer.
- __Config__: Universal ConfigMaps that should be applied to all namespaces.

```sh
kubectl apply -f _init
```

## Notes for v1.26+
v1.26 removes native gluster support. I've swapped to `nfs-ganesha`:

## [CP] /etc/ganesha/ganesha.conf
```sh
NFS_CORE_PARAM {
        mount_path_pseudo = true;
        Protocols = 3,4,9P;
}


EXPORT
{
        Export_Id = 1;
        Path = "bulk";

        FSAL {
                name = GLUSTER;
                hostname = "10.0.8.254";
                volume = "glass_bulk";
        }

        Access_type = RW;
        Squash = No_root_squash;
        Disable_ACL = TRUE;
        Pseudo = "/bulk";
        Protocols = 3,4;
        Transports = "UDP","TCP";
        SecType = "sys";
}

EXPORT
{
        Export_Id = 2;
        Path = "cfg"; 

        FSAL {
                name = GLUSTER;
                hostname = "10.0.8.254";
                volume = "glass_cfg";
        }
        Access_type = RW;
        Squash = No_root_squash;
        Disable_ACL = TRUE;
        Pseudo = "/cfg";
        Protocols = 3,4;
        Transports = "UDP","TCP";
        SecType	= "sys";
}

```

## Verify Installation Success (You Hope)
Should resolve: http://127.0.0.1:9000/dashboard/
```sh
kubectl port-forward $(kubectl get pods --selector "app.kubernetes.io/name=traefik" --output=name) 9000:9000
```
