# UniFi Network API

Agent-facing operational notes. Endpoint/schema reference lives elsewhere — do not
restate it here.

- Index: <https://developer.ui.com/network/v${VERSION}$/llms.txt>

Scope: UniFi **Network** only. Not Site Manager / Access / Protect / Talk.

## Access

```sh
curl -k -sS 'https://10.0.0.1/proxy/network/integration/v1/sites' \
  -H "X-API-KEY: ${UNIFI_API_KEY}" -H 'Accept: application/json'
```

- Base: `https://10.0.0.1/proxy/network/integration/v1`
- Auth: `X-API-KEY` header. No cookie, no CSRF. Bad/missing key → `401`.
- `-k` required: console cert is self-signed.
- Key is **console**-scoped, not site-scoped. Lives in `.env` (gitignored).

## Change policy

Reads (`GET`) are free. Writes (`POST`/`PUT`/`PATCH`/`DELETE`) happen only with
explicit per-change approval — never as a side effect of exploring.

Reason: key has full network authority; a bad write cuts the link the agent runs over.

## Credentials / Env Vars

`bin/unifi-env` sources the repo `.env` (gitignored) and exports required `UNIFI_*` variables.
It does nothing else — no client, no policy.

```sh
. bin/unifi-env
curl -k -sS "$UNIFI_BASE/info" -H "X-API-KEY: $UNIFI_API_KEY"
```

Python/other runtimes: read `.env` directly, same variable names.

## Gotchas

- **Site UUID ≠ site name.** Everything nests under `/sites/{siteId}` where `siteId`
  is a UUID. The `internalReference` field (`default`) is the legacy name and is not
  interchangeable. Available site IDs are provided in `.env` under `SITE_UUIDS`; if multiple
  UUIDs are provided, query the user to disambiguate. Assume all session work is sticky to
  the same Site unless user explicitly redirects to a different site.
- **Fetching OpenAPI Spec** Substituting version provided by (`GET /info`), the OpenAPI
  JSON spec can be fetched at `https://developer.ui.com/network/v${VERSION}/openapi.json`.
- **Rule order is a separate call.** List order from `firewall/policies` and
  `acl-rules` is not evaluation order — read `.../ordering`. Predefined system rules
  are outside that list.
- **Pagination:** `?offset=&limit=` , default `limit=25`. Loop until
  `offset + count >= totalCount`. Lists return an envelope, detail endpoints return
  the bare object.
- **Not exposed here:** port profiles, static routes, port forwarding, DHCP options,
  per-port config, event history, historical stats. Those need the legacy private
  `/api/s/{site}/…` API (cookie + CSRF, unversioned, unsupported).

## House rules for all sibling documentation (anything in `docs/unifi`)

This is a public repo. Do not include keys, site UUIDs, MACs, WAN IPs in markdown.
These secret values belong in the `.env` and should only be referenced.
