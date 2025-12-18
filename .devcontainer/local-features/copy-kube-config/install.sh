#!/usr/bin/env bash
set -e

USERNAME="${USERNAME:-"${_REMOTE_USER}"}"

# Script copies localhost's ~/.kube/config file into the container and swaps out 
# localhost for host.docker.internal on bash/zsh start to keep them in sync.
cp copy-kube-config.sh /usr/local/share/

chown ${USERNAME}:root /usr/local/share/copy-kube-config.sh
echo "source /usr/local/share/copy-kube-config.sh" | tee -a /root/.bashrc >> /root/.zshrc
if [ ! -z "${USERNAME}" ] && [ "${USERNAME}" != "root" ]; then
    echo "source /usr/local/share/copy-kube-config.sh" | tee -a /home/${USERNAME}/.bashrc >> /home/${USERNAME}/.zshrc
fi

curl -L https://github.com/projectcalico/calico/releases/download/v3.25.1/calicoctl-linux-amd64 -o calicoctl
chmod +x ./calicoctl
sudo mv calicoctl /usr/local/bin/

sudo apt update
sudo apt install -y python3-pip python3-yaml sshpass

