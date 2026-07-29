# Ansible Playbooks for Kubernetes Bare Metal Cluster

## Upgrade Kubernetes 1.34 to 1.36

Kubernetes minor releases cannot be skipped, so `60-upgrade-kubernetes.yaml`
upgrades the control plane and then each worker to 1.35 before repeating the
process for 1.36. It selects the latest patch available in each minor release.

Back up the cluster and application data first. Then run:

```shell
ansible-playbook -i inventory/hosts.yml 60-upgrade-kubernetes.yaml \
  -e kubernetes_upgrade_backup_confirmed=true
```

Nodes are drained and upgraded one at a time. A drain fails rather than deleting
pods that use `emptyDir` by default. After verifying that losing that ephemeral
data is acceptable, opt in with:

```shell
-e kubernetes_delete_emptydir_data=true
```

Kubernetes 1.36 defaults to rejecting cgroups v1. The playbook checks every
node for cgroups v2 before performing the 1.36 step.

The playbook also verifies each node's RPM database before changing packages.
If corruption is found, repair is deliberately opt-in. The repair creates a
backup under `/var/preserve`, rebuilds the database, restores SELinux labels,
and verifies it again:

```shell
-e kubernetes_repair_rpmdb=true
```
