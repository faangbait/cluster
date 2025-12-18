#!/bin/bash
USERNAME=ss

echo "alias k=kubectl" >> ~/.bashrc

pip install ansible
ansible-galaxy collection install ansible.posix

mkdir -p ~/.ssh
tee -a ~/.ssh/config << END
Host node*
  User ${USERNAME}
  StrictHostKeyChecking no
END