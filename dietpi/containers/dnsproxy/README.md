# DNS-over-HTTPS Proxy Container

Encrypts the DNS traffic leaving this box. Pi-hole speaks plain DNS to this
proxy on loopback; the proxy speaks DoH (HTTPS) to Quad9.

Runs [AdGuard dnsproxy](https://github.com/AdguardTeam/dnsproxy) — a plain
DNS-to-DoH forwarder driven entirely by flags. No account, no cloud component;
it only talks to the DoH endpoint `.env` names.

**Why not cloudflared:** this originally used `cloudflared proxy-dns`, the
classic Pi-hole DoH sidecar. Cloudflare **removed** that feature in release
2026.2.0 — the container now exits with *"dns-proxy feature is no longer
supported"*. Do not switch back.

## Query path

```
LAN client -> pihole :53 -> dnsproxy 127.0.0.1:5053 -> HTTPS -> Quad9
```

The host itself (`/etc/resolv.conf`) is deliberately NOT in that path. It keeps
using plaintext Quad9 IPs, because:

- `resolv.conf` has no syntax for a port, so it cannot use `127.0.0.1:5053`.
- This container needs working DNS *before* it can resolve its own DoH
  hostname. Pointing the host at Pi-hole (or at this proxy) creates a startup
  deadlock, or the DNS loop documented in `ansible/roles/network/`.

So the host's own lookups (apt, GitHub, DietPi updates) stay unencrypted. All
LAN client traffic is encrypted.

## Configuration

### Environment Variables (.env)

- `TZ`: Timezone
- `DNSPROXY_PORT`: Loopback port Pi-hole forwards to (default: 5053)
- `DNSPROXY_UPSTREAM_1` / `_2`: DoH endpoints
- `DNSPROXY_BOOTSTRAP_1` / `_2`: plaintext resolvers (`ip:53`) used *only* to
  look up the DoH hostnames at startup. Never point these at the local Pi-hole:
  it forwards here, so the two would deadlock on boot.

Defaults are Quad9: `dns11` (malware filtering + ECS, the encrypted equivalent
of `9.9.9.11`) with `dns` (malware filtering, no ECS) as secondary. Keep these
in sync with `dns_doh_upstreams` in `ansible/group_vars/all.yml`.

Other providers, if you ever want to switch:

| Provider              | Endpoint                                   |
|-----------------------|--------------------------------------------|
| Quad9 malware+ECS     | `https://dns11.quad9.net/dns-query`        |
| Quad9 malware         | `https://dns.quad9.net/dns-query`          |
| Quad9 unfiltered      | `https://dns10.quad9.net/dns-query`        |
| Cloudflare            | `https://cloudflare-dns.com/dns-query`     |
| Cloudflare malware    | `https://security.cloudflare-dns.com/dns-query` |

### Pi-hole side

`containers/pihole/pihole.toml` sets `upstreams = ["127.0.0.1#5053"]`. On an
already-running Pi-hole the repo file is not re-read (it is only seeded on a
fresh install), so `ansible/roles/pihole/` applies it live with
`pihole-FTL --config`.

## Usage

```bash
docker compose up -d          # start
docker compose logs -f        # follow logs
bash update_dnsproxy.sh       # pull + recreate + verify + prune
```

## Verifying

```bash
# proxy answers on loopback
dig @127.0.0.1 -p 5053 example.com

# full path through Pi-hole
dig @192.168.1.100 example.com

# DNSSEC still validates end to end (expect: ad flag, NOERROR)
dig @192.168.1.100 cloudflare.com +dnssec | grep -E 'flags:|status:'

# no plaintext client queries leaving the box
# (only the host's own lookups and the router should appear)
sudo tcpdump -ni eth0 'port 53'
```

## Health checks

Two layers, because they prove different things:

- **Container healthcheck** (`nc -z 127.0.0.1 5053`): liveness only — the
  listener is up. Shows as "healthy" in Portainer.
- **Host-side `dig`** in `update_dnsproxy.sh` and `roles/dnsproxy`: end to end,
  proving the DoH upstream actually answers.

Only the second one catches a proxy that starts and listens but cannot resolve.
That is exactly how the `cloudflared` removal was caught: the container was
"running", the port was open, and every query failed.

No Prometheus metrics: AdGuard dnsproxy exposes none (only `--pprof`). Query
visibility comes from Pi-hole's own stats, which sit in front of this anyway.

## Troubleshooting

**Nothing resolves on the LAN.** Check this container first — it is a single
point of failure for every client query:

```bash
docker logs dnsproxy --tail 50
dig @127.0.0.1 -p 5053 example.com
```

**Container starts then exits / cannot resolve upstream.** It could not look up
its DoH hostname. Bootstrap DNS is broken:

```bash
cat /etc/resolv.conf          # must list upstream IPs, never 127.0.0.1 or the Pi's own IP
getent hosts dns11.quad9.net
```

Re-apply with `ansible-playbook -i inventory.yml playbook.yml --tags network`.

**Every query fails but the container is "running".** Check the logs for a
removed or renamed flag after an image update — this is a floating tag:

```bash
docker logs dnsproxy --tail 20
```

**DNSSEC answers come back BOGUS.** Almost always the clock, not this proxy.
RRSIG validity windows fail when the system clock is skewed:

```bash
timedatectl | grep -E "synchronized|NTP service"
```

See `ansible/roles/system/vars/main.yml` for the full explanation.
