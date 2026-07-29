#!/usr/bin/env bash
set -euo pipefail

USERNAME="${USERNAME:-${_REMOTE_USER:-root}}"

# Install the shell hook that keeps the mounted kube config synchronized.
cp copy-kube-config.sh /usr/local/share/
chown "${USERNAME}:root" /usr/local/share/copy-kube-config.sh
printf '%s\n' "source /usr/local/share/copy-kube-config.sh" | tee -a /root/.bashrc >> /root/.zshrc

if [[ -n "$USERNAME" && "$USERNAME" != root ]]; then
    printf '%s\n' "source /usr/local/share/copy-kube-config.sh" \
        | tee -a "/home/${USERNAME}/.bashrc" >> "/home/${USERNAME}/.zshrc"
fi

curl -L https://github.com/projectcalico/calico/releases/download/v3.25.1/calicoctl-linux-amd64 -o calicoctl
chmod +x ./calicoctl
mv calicoctl /usr/local/bin/

apt-get update
apt-get install -y python3-pip python3-yaml sshpass
