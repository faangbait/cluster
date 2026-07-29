#!/bin/bash -i

# Copies localhost's kube config into the container and replaces localhost with
# host.docker.internal whenever a new shell starts.
if [[ "${SYNC_LOCALHOST_KUBECONFIG:-false}" == "true" && -d /usr/local/share/kube-localhost ]]; then
    mkdir -p "$HOME/.kube"
    sudo cp -r /usr/local/share/kube-localhost/. "$HOME/.kube/"
    sudo chown -R "$(id -u)" "$HOME/.kube"
    sed -i -e "s/localhost/host.docker.internal/g" "$HOME/.kube/config"
    sed -i -e "s/127.0.0.1/host.docker.internal/g" "$HOME/.kube/config"
fi
