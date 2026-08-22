# Internal DNS — retro

The internal-DNS spec as built. Everything below is live and verified.

## Functional requirements

| ID | Requirement |
| --- | --- |
| FR-1 | LAN clients resolve every cluster hostname to `10.4.0.2`. |
| FR-2 | Off-LAN clients resolve published hostnames to the WAN address. |
| FR-3 | Same hostname, same certificate, valid on both paths. |
| FR-4 | DHCP hands out `10.0.0.1` as the resolver. |
| FR-5 | The UDM answers its static records locally and forwards everything else upstream. |
| FR-6 | The internal instance reads IngressRoute and Ingress. |
| FR-7 | The public instance reads IngressRoute only. Ingress objects stay LAN-only. |
| FR-8 | The internal instance writes UniFi static-DNS through the webhook provider. |
| FR-9 | The public instance writes Route53 through the aws provider. |
| FR-10 | The instances are told apart by `--annotation-prefix`: `external-dns.internal/` and `external-dns.public/`. |
| FR-11 | Separate `--txt-owner-id` per instance. Neither touches the other's records. |
| FR-12 | Both instances carry the same tier `--domain-filter` list, matching Authelia's `access_control`. |
| FR-13 | `--policy=upsert-only` on both. ExternalDNS never deletes. |
| FR-14 | `--aws-zone-match-parent` so tier names resolve against the parent zone. |
| FR-15 | `--aws-zone-type=public` scopes the public instance. No zone id in the repo. |
| FR-16 | A published route carries `external-dns.internal/target` and `external-dns.public/publish`. |
| FR-17 | `external-dns.public/target` is never authored. The wan-target CronJob stamps it from the live WAN address. |
| FR-18 | Authelia is `sso.vault.madeof.glass`. `sso.madeof.glass` is retired. |
| FR-19 | Authelia's bypass rule for its own hostname sits above the `*.vault` one_factor rule. |
| FR-20 | ExternalDNS owns the tier records. Terraform does not. |
| FR-21 | Terraform keeps the apex: MX, SPF, `_dmarc`, delegation. No apex `A` — the apex is never served through the cluster. |
| FR-22 | Per-name records only. No wildcards in either view. |
| FR-23 | Authelia's session cookie, TOTP issuer, and default redirect are scoped to the primary domain, not to any one tier. |
| FR-24 | Traefik sees the real client source address. No hairpin. |
| FR-25 | Live IngressRoutes match their repo source. |
| FR-26 | Tier domains are enumerated, one `--domain-filter` per tier. |

## Non-functional requirements

| ID | Requirement |
| --- | --- |
| NFR-1 | A missing annotation yields no record. No placeholder value can yield a wrong one. |
| NFR-2 | Adding or removing an annotation converges within one reconcile interval. |
| NFR-3 | A tier missing from `--domain-filter` is silent — its records are never published and nothing reports it. |
| NFR-4 | Without `--aws-zone-match-parent` the public instance matches zero zones and publishes nothing. |
| NFR-5 | Distinct owner IDs keep the two registries independent. |
| NFR-6 | A provider error is soft: existing records are untouched and the controller self-recovers. |
| NFR-7 | Neither instance is in the resolution path. Both only write. |
| NFR-8 | Reconcile runs at 1m and converges without intervention. |
| NFR-14 | No new listener and no new reachability on the request path. |
| NFR-15 | Verify split-horizon with `dig`, never `nslookup`, and run the public-view leg from off-LAN. |

## TODO — a browser with DoH enabled bypasses split-horizon entirely

The UDM DNATs all outbound port 53, which is what makes split-horizon work — but
only on port 53. DNS-over-HTTPS rides 443 and is indistinguishable from ordinary
web traffic, so a client that resolves over DoH never consults the UDM at all,
and therefore never sees UniFi static-DNS.

Measured from a host on the LAN, in the same second:

| Name | via port 53 | via DoH (Cloudflare and Google) |
| --- | --- | --- |
| `sso.vault.madeof.glass` | `10.4.0.2` | `<WAN address>` |
| `test.mon.madeof.glass` | `10.4.0.2` | `<WAN address>` |
| `grafana.mon.madeof.glass` | `10.4.0.2` | **NXDOMAIN** |

This is not a hypothetical configuration. Firefox enables DoH by default for
users in the US and several other regions. Chrome and Edge auto-upgrade when the
system resolver is a recognised DoH provider — not the case here, since the
system resolver is the UDM — so Firefox is the immediate exposure, plus anything
deliberately pointed at a DoH endpoint.

**Consequences, worst first.**

1. **LAN-only names break outright.** `grafana`, `prom` and `alerts` return
   NXDOMAIN over DoH. In a DoH browser on the LAN they are simply unreachable.
   This is a hard failure, not a slow path, and it is the direct downside of the
   deliberate posture that those names exist *only* in UniFi.
2. **Hairpinning returns for those clients.** `sso` and `test.mon` resolve to
   the WAN address, so the request leaves the LAN, hits the border and is
   NAT-reflected back — precisely the behaviour this project set out to remove.
   FR-1 is defeated for that client.
3. **FR-24 is defeated with it.** A hairpinned request reaches Traefik with the
   WAN address in `X-Forwarded-For`, not the client's LAN address. Anything
   IP-based sees the wrong input, and it will look intermittent because it
   depends on the browser rather than the host.

**Neither FR-1 nor FR-24 is downgraded here.** Both were validated against the
system resolver, which is what the design specifies and what non-browser traffic
uses. But both are conditional on the client actually asking the UDM, and no
requirement in the approved set states that condition. That is the gap.

This was not theoretical when it was found. It was the live symptom: names
would not resolve in the browser while `dig` on the same machine answered
correctly. The browser was on DoH.

### Fix: exclude `madeof.glass` from DoH, per client

Leave DoH on for everything else and carve out the one domain that has an
internal view. Nothing in the cluster or on the UDM changes, which keeps this
clear of C-4.

**Firefox** — the only browser that supports this directly.

`about:config` → `network.trr.excluded-domains`, append `madeof.glass`. The
value is a comma-separated list and each entry covers its subdomains, so one
entry catches all eight tiers. There is no glob syntax; `*.madeof.glass` is not
a valid entry — `madeof.glass` is what you write, and it does the same job.

Fleet-wide, the same thing via enterprise policy (`policies.json`):

```json
{ "policies": { "DNSOverHTTPS": { "ExcludedDomains": ["madeof.glass"] } } }
```

**Chrome and Edge** have no per-domain exclusion list — DoH is on or off, and a
DoH NXDOMAIN does not fall back to the system resolver. In practice this is
mostly moot here: both only auto-upgrade when the system resolver is a
recognised DoH provider, and the UDM is not one, so they stay on port 53 and
resolve correctly already. A client that opted in explicitly needs
`DnsOverHttpsMode: off` by policy, or a DoH endpoint of our own that serves the
internal view.

**Safari** follows the system resolver unless a configuration profile overrides
it, so it needs nothing.

**Cost of this approach:** it is per-client and manual. Every new device is
broken until someone sets it, and guest devices are never going to be. The
fleet-wide alternative is the Firefox canary domain — returning NXDOMAIN for
`use-application-dns.net` on the UDM makes Firefox disable DoH by itself, no
per-device step. That is a structural UDM change and needs approval under C-4,
so it stays on the table rather than in the build.

Either way the symptom is worth writing down, because it points nowhere near
DNS: *"it works on my phone but not my laptop."*
