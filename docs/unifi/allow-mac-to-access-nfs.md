# Add a MAC to the gluster NFS allowlist

Get access to Unifi API: @access-unifi-api.md — base URL, auth, `.env`, pagination, and
the write-approval policy all live there. Not repeated here.

Every snippet below assumes:

```sh
. bin/unifi-env
SITE_ID=$SITE_UUIDS   # single site; disambiguate per access-unifi-api.md if several
```

## What you are editing

One ZBF policy, named:

```
6.2 Userland -> Serverland (NFS, named hosts)
```

It is the only exception to `userland → serverland: deny`. Shape:

- **source** zone Userland, `trafficFilter.type = MAC_ADDRESS`, holding the allowlist
- **destination** zone Serverland, ports `111` and `2049`
- protocol preset `TCP_UDP`

MAC matching is **source-side only** in ZBF — there is no destination MAC filter. That is
why the allowlist lives on this one policy rather than somewhere more discoverable.

Adding a client is therefore a single operation: append its MAC to `macAddresses`. No new
policy, no DHCP reservation, no IP address anywhere in the config.

## Steps

**1. Find the policy ID by name.** IDs are not stable across rebuilds — never hardcode one.

```sh
POLICY_ID=$(curl -k -sS "$UNIFI_BASE/sites/$SITE_ID/firewall/policies?limit=500" \
  -H "X-API-KEY: $UNIFI_API_KEY" \
  | jq -r '.data[] | select(.name | startswith("6.2 Userland -> Serverland")) | .id')
```

**2. Read the current object.** You need all of it — step 4 sends it back intact.

```sh
curl -k -sS "$UNIFI_BASE/sites/$SITE_ID/firewall/policies/$POLICY_ID" \
  -H "X-API-KEY: $UNIFI_API_KEY" > /tmp/nfs-policy.json

jq '.source.trafficFilter.macAddressFilter.macAddresses' /tmp/nfs-policy.json
```

**3. Confirm the MAC is real and sits in userland.** A typo fails in the confusing
direction: the client is denied silently and it presents as an NFS or mount problem.

```sh
curl -k -sS "$UNIFI_BASE/sites/$SITE_ID/clients?limit=200" \
  -H "X-API-KEY: $UNIFI_API_KEY" \
  | jq -r '.data[] | "\(.macAddress)  \(.ipAddress)  \(.name)"' | grep -i "$NEW_MAC"
```

The reported address must be inside userland's `10.2.0.0/23`. A client in another zone is
not covered by this policy and needs a different conversation, not a longer allowlist.

**4. Append, then PUT the whole object back.** Read-modify-write. `PATCH` exists, but
partial updates of the nested filter are not worth the risk.

```sh
jq --arg m "$NEW_MAC" \
  '.source.trafficFilter.macAddressFilter.macAddresses += [$m]' \
  /tmp/nfs-policy.json > /tmp/nfs-policy-new.json

curl -k -sS -X PUT "$UNIFI_BASE/sites/$SITE_ID/firewall/policies/$POLICY_ID" \
  -H "X-API-KEY: $UNIFI_API_KEY" -H 'Content-Type: application/json' \
  --data @/tmp/nfs-policy-new.json
```

Lowercase, colon-separated (`aa:bb:cc:dd:ee:ff`). The field is `uniqueItems`, so a
duplicate is rejected rather than silently merged.

**5. Verify**, then mount from the client:

```sh
curl -k -sS "$UNIFI_BASE/sites/$SITE_ID/firewall/policies/$POLICY_ID" \
  -H "X-API-KEY: $UNIFI_API_KEY" \
  | jq '.source.trafficFilter.macAddressFilter.macAddresses | length, .'
```

## Host-level rules are separate

This policy only gets the packet to the node. The node's own `firewalld` decides whether
it is served — see Stage 6.3 in `../migration-rollout.md`.

**firewalld rich rules cannot match MAC**; they match source addresses only. So a client
added here and nowhere else still fails if firewalld is restricting NFS by address.

If NFS still fails after this change, check firewalld on the node before re-reading
anything above.

## Removing a MAC

Same shape, `-=` instead of `+=`:

```sh
jq --arg m "$OLD_MAC" \
  '.source.trafficFilter.macAddressFilter.macAddresses -= [$m]' \
  /tmp/nfs-policy.json > /tmp/nfs-policy-new.json
```

`minItems: 1` — emptying the list is rejected. To revoke the last remaining client, delete
the policy instead, which restores a flat `userland → serverland` deny.
