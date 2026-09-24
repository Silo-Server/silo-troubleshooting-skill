# Networking, reverse proxies, and remote access

Use this when Silo works on the LAN but not remotely, the web app loads but
live updates or playback fail, you see redirect loops or mixed-content errors,
or apps cannot find the server.

## Ports

| Container port | Default host port (`.env`) | Purpose |
|---|---|---|
| `8080` | `PORT=8090` | Web app and native API |
| `8096` | `JF_PORT=8096` | Jellyfin/Emby-compatible clients |
| `13378` | `ABS_PORT=13378` | Audiobookshelf-compatible clients (beta) |

The Docker Compose file fixes the container ports; `.env` changes only the host
side. These listeners do not serve TLS. PostgreSQL (5432) and Redis (6379) are
published on `127.0.0.1` only by default and must never be exposed publicly.

## Test from the inside out

Run each step and stop at the first one that fails:

```sh
# 1. From the Docker host, straight to the container
curl -fsS http://localhost:8090/api/v1/health
curl -fsS http://localhost:8090/api/v1/ready

# 2. From another machine on the LAN
curl -fsS http://<host-lan-ip>:8090/api/v1/health

# 3. Through the reverse proxy
curl -fsSI https://media.example.com/api/v1/health
```

- 1 fails: Silo is not running or not healthy. See `startup-and-database.md`.
- 1 passes, 2 fails: host firewall or port mapping.
- 2 passes, 3 fails: reverse proxy, DNS, or TLS certificate.

`health` shows the process is alive. `ready` also checks required dependencies
(PostgreSQL and any configured S3 storage).

## Reverse proxy requirements

Silo expects the proxy to:

1. **Forward WebSockets.** Live updates, admin log streaming, remote playback
   control, and Watch Together all use WebSockets. Nginx needs the `Upgrade`
   and `Connection` headers passed through; Caddy and Traefik do this by
   default.
2. **Preserve `Host`.**
3. **Overwrite `X-Forwarded-Proto`, never append to it.** Silo ignores the
   header if it carries more than one value, then treats the request's scheme
   as unknown. That breaks WebSocket origin checks and HTTPS detection. Chains
   of proxies (Cloudflare Tunnel → Nginx → Silo, for example) are the usual
   cause.
4. **Send `X-Forwarded-For`** so Silo sees real client addresses.
5. **Allow long responses and large bodies.** Streams run for hours, and
   client diagnostic uploads can be large. Disable response buffering and
   raise read timeouts for Silo's location.

Minimal Nginx example to compare against (not a drop-in config):

```nginx
location / {
    proxy_pass http://127.0.0.1:8090;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;  # needs the usual map block
    proxy_buffering off;
    proxy_read_timeout 1h;
    client_max_body_size 0;
}
```

Behind a second TLS terminator (Cloudflare, a load balancer, a tunnel), Nginx's
`$scheme` is `http`. In that case pass the original header through once
(`proxy_set_header X-Forwarded-Proto https;` or the value from the outer
proxy), never both. In Nginx Proxy Manager, turn on **Websockets Support** for
the proxy host.

## Silo settings that must match the proxy

- **Silo public URL** (`server.public_url`, **Admin > Settings > General**):
  the exact external origin, for example `https://media.example.com`, with no
  path and no trailing slash. WebSocket connections from browsers are accepted
  only when their `Origin` matches this URL or the request's own scheme and
  host, so a wrong or empty value shows up as the web app loading while live
  updates never connect.
- **Trusted proxies** (`clientip.trusted_proxies`, **Admin > Settings >
  Security & Access**; the `SILO_TRUSTED_PROXIES` environment variable
  overrides it). Silo honours forwarding headers only from these addresses.
  The default is the private ranges plus loopback:
  `10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8, ::1/128`.
  - If the proxy reaches Silo from a public address (a VPS, Cloudflare), add
    that address, or every client appears to come from the proxy.
  - If you narrow the list, keep loopback. Silo's network-access plugins rely
    on it.
  - Wrong trust makes remote clients look local (or the reverse), which
    changes whether Silo classifies a stream as local or remote.
- **Address Jellyfin apps should use** (`jellyfin_compat.public_url`,
  **Admin > Settings > Compatibility**) if Jellyfin clients connect through a
  different hostname or port.

Some settings only apply after a restart. The admin UI shows a restart banner
and marks those fields; `GET /api/v2/admin/server/status` reports
`restart_required` and the reasons.

## Apps cannot find or reach the server

- Native Silo apps and Jellyfin-compatible apps need the URL they can actually
  reach, including `https://` and a non-default port if one is used.
- Jellyfin clients connect to port `8096` (or `JF_PORT`), not `8090`. If
  Jellyfin itself still runs on the same machine, it holds port 8096 and Silo
  cannot start its listener (`port is already allocated`).
- Turning on Jellyfin compatibility needs a restart. `GET
  /api/v2/compat/connect-info` returns `pending_restart: true` until then.
- Overlay networks (Tailscale-style network-access plugins) are managed under
  **Admin > Settings > Network Access**. A provider that failed ten times in a
  row stays failed until an admin restarts it from **Admin > Plugins** (or
  `POST /api/v2/admin/plugins/installations/{id}/restart`).

## Do not

- Do not publish PostgreSQL or Redis ports to the internet to "make remote
  access work".
- Do not set trusted proxies to `0.0.0.0/0`. Anyone could then spoof their
  client address.
- Do not disable TLS verification or switch the public URL to `http://` to hide
  a certificate problem. Fix the certificate.
