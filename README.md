# K8s Standup on Rocky 9.4

## Important
This documentation assumes you've navigated to this directory in your file tree (`cat README.md` returns this doc). Run commands on all nodes unless prefixed with "[CP]" - these should run on a _single_ control-plane node.

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

## Run Ansible Playbooks

- See `ansible` folder
- `10-provision-cluster.yaml` - Provisions a fresh Rocky 9.7 box 
- `20-bootstrap-gluster.yaml` - Installs and configures glusterfs
- `30-bootstrap-control-plane.yaml` - Installs Kubernetes on Control Plane
- `40-bootstrap-workers.yaml` -  Installs Kubernetes on Workers
- `50-bootstrap-applications.yaml` -  Installs necessary manifests (CNI, etc)

## Consider Installing Bootstraps Provided in _init Subfolder
These are highly workflow-dependent, but this is what I use.
- __Namespaces__: we don't want to provision these from inside a yaml file that we'd later accidentally `kubectl delete`, so I do them all at once here.
- __Storage__: I'd have preferred to run Ceph, but since I'm hosting the storage cluster on the same bare metal machines as k8s, the container runtime requirements can and will conflict. You'll end up with a dead K8s or a dead Ceph sooner or later. [Gluster Installation Instructions](https://docs.rockylinux.org/guides/file_sharing/glusterfs/).
- __Authentication__: I selected Authelia as a universal authentication layer.
- __Config__: Universal ConfigMaps that should be applied to all namespaces.

```sh
kubectl apply -f _init
```

## Verify Installation Success (You Hope)
Should resolve: http://127.0.0.1:9000/dashboard/
```sh
kubectl port-forward $(kubectl get pods --selector "app.kubernetes.io/name=traefik" --output=name) 9000:9000
```
