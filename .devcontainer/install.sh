#!/bin/bash
set -euo pipefail

DEVCONTAINER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
containerWorkspaceFolder="$(dirname -- "$DEVCONTAINER_DIR")"
export containerWorkspaceFolder

sudo apt update && sudo apt install -y ripgrep ncat

sudo ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime && sudo dpkg-reconfigure -f noninteractive tzdata

echo alias tf=terraform > ~/.bash_aliases

curl -fsSL https://claude.ai/install.sh | bash

curl -fsSL https://opencode.ai/install | bash

npx --yes @slkiser/opencode-quota init || true

curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh

curl -sSL https://raw.githubusercontent.com/8b-is/smart-tree/main/scripts/install.sh | bash

curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | jq -r '.tag_name')/install.sh" | bash

bash -c "source ~/.nvm/nvm.sh && nvm install 24 --latest-npm --no-progress && npm install -g context-mode" || bash -c "npm install -g context-mode"

mkdir -p "${containerWorkspaceFolder}"/.github/hooks

wget https://raw.githubusercontent.com/mksglu/context-mode/refs/heads/main/configs/vscode-copilot/hooks.json -O .github/hooks/context-mode.json

pipx install spec-kitty-cli

echo "alias k=kubectl" >> ~/.bashrc

pip install ansible && ansible-galaxy collection install ansible.posix

mkdir -p ~/.ssh

printf 'Host node*\n  User ss\n  StrictHostKeyChecking no\n' >> ~/.ssh/config
