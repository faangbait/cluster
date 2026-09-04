# Runbook: PostgreSQL major-version upgrade

Preserved verbatim from the header of the old `_init/70-postgresql.yaml`, which
was migrated into `ansible/roles/deploy-postgresql/`. This is a one-off manual
procedure, not an install step, so it was deliberately **not** converted into
ansible tasks: it scales consumers down, moves `PGDATA` aside by hand, and
depends on a human watching each dump succeed before the old data directory is
destroyed.

**PostgreSQL is not currently deployed.** There is no `postgresql` helm release
and no postgres StatefulSet in the cluster. This runbook is kept for the day it
comes back; `ansible/roles/deploy-postgresql/` is written but has no playbook.

## Why a dump/restore at all

A bitnami/postgresql major bump changes the on-disk `PGDATA` format. The new
server will refuse to start against the old directory, so the data has to make
the trip as SQL.

## Procedure

### Local

```sh
helm repo update
k scale --replicas=0 statefulset/{lidarr,sonarr,radarr,readarr} -n news
k exec -it pod/postgresql-client -n lab -- /bin/sh
```

### In the client shell — dump

```sh
read PGPASSWORD
PGPASSWORD=${PGPASSWORD} pg_dump -w -U postgres -h postgresql.lab.svc.cluster.local -f dump.sql
PGPASSWORD=${PGPASSWORD} pg_dump -w -U postgres -h postgresql.lab.svc.cluster.local -d radarr-main -f radarr-main.sql
PGPASSWORD=${PGPASSWORD} pg_dump -w -U postgres -h postgresql.lab.svc.cluster.local -d readarr-main -f readarr-main.sql
PGPASSWORD=${PGPASSWORD} pg_dump -w -U postgres -h postgresql.lab.svc.cluster.local -d lidarr-main -f lidarr-main.sql
PGPASSWORD=${PGPASSWORD} pg_dump -w -U postgres -h postgresql.lab.svc.cluster.local -d sonarr-main -f sonarr-main.sql
PGPASSWORD=${PGPASSWORD} pg_dump -w -U postgres -h postgresql.lab.svc.cluster.local -d radarr-log -f radarr-log.sql
PGPASSWORD=${PGPASSWORD} pg_dump -w -U postgres -h postgresql.lab.svc.cluster.local -d readarr-log -f readarr-log.sql
PGPASSWORD=${PGPASSWORD} pg_dump -w -U postgres -h postgresql.lab.svc.cluster.local -d lidarr-log -f lidarr-log.sql
PGPASSWORD=${PGPASSWORD} pg_dump -w -U postgres -h postgresql.lab.svc.cluster.local -d sonarr-log -f sonarr-log.sql
```

### Local — swap the data directory and upgrade

```sh
k scale --replicas=0 statfulset/postgresql-0 -n lab
sudo mv /mnt/replicated/pvc/lab/data-postgresql-0/data /mnt/replicated/pvc/lab/data-postgresql-0/old_data
helm get values postgresql -n lab > /tmp/postgres-values.yaml
helm upgrade postgresql bitnami/postgresql -n lab -f /tmp/postgres-values.yaml
```

There is no checked-in values file to point at — the values are inlined in
`ansible/61-add-postgresql.yaml`. Reading them back off the live release is
what you want here anyway: this upgrade must not also apply unrelated drift
between the playbook and what is actually running.

### In the client shell — restore

```sh
PGPASSWORD=${PGPASSWORD} psql -w -U postgres -h postgresql.lab.svc.cluster.local < dump.sql
PGPASSWORD=${PGPASSWORD} psql -w -U postgres -h postgresql.lab.svc.cluster.local radarr-main < radarr-main.sql
PGPASSWORD=${PGPASSWORD} psql -w -U postgres -h postgresql.lab.svc.cluster.local readarr-main < readarr-main.sql
PGPASSWORD=${PGPASSWORD} psql -w -U postgres -h postgresql.lab.svc.cluster.local lidarr-main < lidarr-main.sql
PGPASSWORD=${PGPASSWORD} psql -w -U postgres -h postgresql.lab.svc.cluster.local sonarr-main < sonarr-main.sql
PGPASSWORD=${PGPASSWORD} psql -w -U postgres -h postgresql.lab.svc.cluster.local radarr-log < radarr-log.sql
PGPASSWORD=${PGPASSWORD} psql -w -U postgres -h postgresql.lab.svc.cluster.local readarr-log < readarr-log.sql
PGPASSWORD=${PGPASSWORD} psql -w -U postgres -h postgresql.lab.svc.cluster.local lidarr-log < lidarr-log.sql
PGPASSWORD=${PGPASSWORD} psql -w -U postgres -h postgresql.lab.svc.cluster.local sonarr-log < sonarr-log.sql

exit
```

### Local — bring consumers back and reclaim

```sh
k scale --replicas=1 statefulset/{lidarr,sonarr,radarr,readarr} -n news
sudo rm -rf /mnt/replicated/pvc/lab/data-postgresql-0/old_data
```

Verify every consumer is healthy before the final `rm -rf`. That is the point of
no return.

## Related

- Gluster `glass_cfg` performance tunables PostgreSQL depends on: `README-gluster.md`
- Playbook and values: `ansible/61-add-postgresql.yaml`
