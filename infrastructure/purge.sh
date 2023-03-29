#!/bin/bash

sudo kubeadm reset -f
sudo rm -rf /etc/cni /etc/kubernetes /var/lib/dockershim /var/lib/etcd /var/lib/kubelet /var/run/kubernetes ~/.kube/*
sudo iptables -F && sudo iptables -X
sudo iptables -t nat -F && sudo iptables -t nat -X
sudo iptables -t raw -F && sudo iptables -t raw -X
sudo iptables -t mangle -F && sudo iptables -t mangle -X
sudo rpm -e kubectl kubeadm kubelet kubernetes-cni
sudo truncate -s0 /home/ss/.kube/config
sudo truncate -s0 /home/kube/.kube/config
sudo chown ss:ss /home/ss/.kube/config
sudo chmod 600 /home/ss/.kube/config
sudo chown kube:kube /home/kube/.kube/config
sudo chmod 600 /home/kube/.kube/config

sudo systemctl restart crio

sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable --now kubelet

# First node only
sudo mkdir -p /etc/kubernetes/config
sudo cp config.mount/* /etc/kubernetes/config/
sudo sed -i "s|REPLACEME|$(head -c 32 /dev/urandom | base64)|g" /etc/kubernetes/config/secret-encryption.yaml
sudo chmod 600 /etc/kubernetes/config/secret-encryption.yaml
sudo chown root:root /etc/kubernetes/config/secret-encryption.yaml
