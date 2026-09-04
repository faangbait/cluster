# K8s on Rocky 9.8

Bare-metal, heterogenous nodes, rootless containers — a first step toward
NSA/CISA hardening guidance. Everything is declarative: nothing is typed into a
terminal except what is in this README.

Run commands on all nodes unless prefixed with `[CP]`, which means one
control-plane node.

---

## Network

MetalLB speaks BGP to the router (nodes AS 65001 ↔ router AS 65000) and
advertises each service VIP as a `/32` into its own routed VLAN. There is no
static route to maintain and no L2 announcement. Traefik's VIP is `10.4.0.2`.

## Host playbooks

Run in number order. `10` and `11` take a fresh box to a configured one; the
rest build the cluster on top.

- `10-provision-cluster.yaml` — provisions a fresh Rocky box
- `11-configure-hosts.yaml` — host-specific variables
- `20-bootstrap-gluster.yaml` — installs and configures GlusterFS, and the metrics exporter that goes with it (`--tags gluster-exporter` to do only that)
- `30-bootstrap-control-plane.yaml` — Kubernetes on the control plane
- `40-bootstrap-workers.yaml` — Kubernetes on the workers
- `50-configure-cluster.yaml` — Calico, then a pass/fail networking test, then
  the namespaces we deploy applications into plus the two things every one of
  them needs — an asserted `regcred` pull secret and the universal
  `lsio-conf` ConfigMap. We don't want to provision namespaces from inside a
  yaml file we'd later accidentally `kubectl delete`, so they're all here.
  Infra namespaces (`traefik`, `metallb`, `cert-manager`, `external-dns`) are
  deliberately absent — they come from their own charts and we don't deploy
  apps into them.

`99-upgrade-kubernetes.yaml` is separate and deliberate: minor versions cannot
be skipped, so it finishes one minor on every node before starting the next. It
refuses to run without an explicit confirmation that the cluster is backed up.

## Cluster playbooks

These used to be hand-run `kubectl apply -f _init` manifests. Every one is a
playbook now. Run them in number order on a fresh cluster; each is non-breaking
and safe to re-run.

- `52-deploy-monitoring.yaml` — __Observability__: kube-prometheus-stack (Prometheus TSDB on emptyDir, Alertmanager on glass-cfg), MinIO on glass-cfg as the Thanos object store, and Thanos query/store/compact. In-cluster services are discovered by `prometheus.io/scrape` pod annotations rather than ServiceMonitors, so adding a target usually means annotating a pod, not writing a CR. The two exceptions are the `gluster` `ScrapeConfig` (built from the inventory — no node address is hardcoded) and the `unifi-dns` secret mirror plus unpoller Deployment (unpoller needs a copy of the console-scoped key `55` asserts in `external-dns`) — both need ansible templating/secret lookups that Flux can't do, so they stay here instead of moving to GitOps with everything else. Deliberately numbered ahead of `54` — MetalLB's own `ServiceMonitor`/`PrometheusRule` need the `monitoring.coreos.com` CRDs this installs.
- `54-deploy-metallb.yaml` — __Load balancing__: MetalLB, its BGP peer and address pool, the node labels its speakers depend on, and its own built-in `ServiceMonitor`/`PrometheusRule` enabled inline — a chart-native toggle, not a hand-rolled scrape target.
- `55-deploy-traefik.yaml` — __Ingress__: Traefik, the `traefik-configmap` its file provider reads, and the split-horizon DNS that makes its routes resolvable — two ExternalDNS instances (UniFi for the LAN view, Route53 for the public view) plus the `wan-target` CronJob that keeps the public target current. Needs `glass-cfg` from `50` for its `acme.json`.
- `56-deploy-authentication.yaml` — __Authentication__: Authelia as a universal authentication layer, its Redis session store, and the Traefik middleware chain that fronts protected routes.
- `57-deploy-flux.yaml` — __GitOps__: the flux-operator, via its OCI chart.
- `60-add-privateregistry.yaml` — __Registry__: the in-cluster image registry.
- `61-add-postgresql.yaml` — __Database__: PostgreSQL. Major-version upgrades are a runbook, not a re-run — see [`docs/runbooks/postgresql-major-upgrade.md`](docs/runbooks/postgresql-major-upgrade.md).

```shell
cd ansible
ansible-playbook -i inventory/hosts.yml 52-deploy-monitoring.yaml
```

`56` and `60` assert that Traefik is deployed and fail with the exact command
to run if it isn't. `55` is the one that has to come first.

`99-*.yaml` (including `99-upgrade-kubernetes.yaml`) is separate and
deliberate, not part of this in-order pass — see
[Host playbooks](#host-playbooks) and each file's own guard.

Every `PrometheusRule`, every `ScrapeConfig` that doesn't need ansible
templating (`limitless-mail`), and everything else that's an opinion about
*this* cluster's services rather than reusable monitoring infrastructure is
Flux-managed GitOps now, not a playbook — see `57-deploy-flux.yaml` and the
`gitops-flux` repo. `81-monitoring-rules.yaml` used to hold all of it; the
only stragglers ansible still has to own are the ones templated from the
inventory or a live secret (Gluster, unifi), and those moved into `52`
directly — see above.

## Conventions

__Secrets are never created by ansible.__ `regcred`, `auth-redis`, the Traefik
and ExternalDNS `aws-credentials`, and the ExternalDNS `unifi-dns` secret
exist only in the live cluster — there is no stored copy, so writing one
would silently replace working credentials. The playbooks look them up and
fail with the exact `kubectl create secret ...` command when one is missing.

__`external-dns/unifi-dns` is the source of truth for the UniFi API key.__ The
key is console-scoped and cannot be narrowed, so there is exactly one of it and
it lives in the `external-dns` namespace. Secrets don't cross namespaces, so
`52` mirrors it into `observability` for unpoller — same name, same
`UNIFI_HOST` / `UNIFI_API_KEY` keys, remapped to unpoller's `UP_*` env vars in
the container spec rather than reshaping the secret. Copying a live secret is
not the same as authoring one, which is why that copy is allowed to be a
playbook task. __Rotate it in `external-dns` and re-run `52`__; never edit the
`observability` copy directly, it is overwritten on every run.

__ExternalDNS target annotations.__ IngressRoutes carry
`external-dns.internal/target` (the Traefik VIP `10.4.0.2`, committed
literally). The public target is the WAN IP, which does not belong in a public
repo, so nothing sets it at deploy time — routes opt in with
`external-dns.public/publish: "true"` and the `wan-target` CronJob stamps the
current address every 5 minutes. Self-healing across a WAN address change, and
no address in git.

__Chart versions are pinned.__ Unpinned, any re-run would upgrade the thing it
was only meant to reconcile. Bump deliberately.

`_init/` is gone; every manifest that lived there is a playbook now.

## Verify

The networking test from `50` is a role, so it can be run on its own:

```shell
ansible-playbook -i inventory/hosts.yml 50-configure-cluster.yaml --tags networking-test
```

Traefik's dashboard, at http://127.0.0.1:9000/dashboard/ :

```shell
kubectl port-forward -n traefik \
  $(kubectl get pods -n traefik --selector "app.kubernetes.io/name=traefik" --output=name | head -1) \
  9000:9000
```
