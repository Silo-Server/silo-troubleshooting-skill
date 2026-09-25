# Metrics and profiling

Read this when a problem keeps coming back or cannot be caught while it
happens: slowdowns, memory growth, out-of-memory restarts, CPU spikes, hangs,
stream drops, or background work that stops moving. Also read it when the
user asks for monitoring.

Upstream references, for details this file leaves out:

- [Monitoring](https://github.com/Silo-Server/silo-server/blob/main/docs/operations/monitoring.md)
- [Profiling](https://github.com/Silo-Server/silo-server/blob/main/docs/operations/profiling.md)

## What Silo offers

Silo has two optional listeners. Both are off by default and separate from the
main port (`8090` on the host, `8080` in the container). The main port serves
neither.

| Setting | Serves | Access control |
|---|---|---|
| `SILO_METRICS_LISTEN` | Prometheus metrics at `/metrics` | None. Network placement is the only protection. |
| `SILO_DEBUG_LISTEN` | Go profiles at `/debug/pprof/` | Loopback addresses only, enforced by Silo. |

Both record only from the moment they are enabled, so they cannot explain an
incident that has already happened. They are for the next occurrence.

## When to offer them

If the problem is recurring or intermittent, and the logs and snapshot do not
explain it, check whether the listeners are already on:

```sh
grep -nE '^SILO_(METRICS|DEBUG)_LISTEN=' .env
docker compose logs --no-log-prefix silo 2>&1 | grep -E 'metrics listener enabled|local profiling listener' | tail -n 2
```

If they are off, tell the user in plain words what each one does, that
enabling them needs a Silo restart, and that it will not help with the current
incident. Then offer two options:

1. Give them the steps below to do it themselves.
2. Make the change for them. This counts as a change: the backup gate and
   one-change-at-a-time consent rules apply.

Do not enable them without asking. Suggest a quiet moment for the restart,
not during playback, a scan, or a migration.

Metrics add little overhead. The profiler costs nothing until someone takes a
capture. Contention sampling (`SILO_DEBUG_BLOCK_RATE`,
`SILO_DEBUG_MUTEX_FRACTION`) adds overhead the whole time it is on; enable it
only for a specific lock-contention question and turn it off afterwards.

## Enable

Values for a single-host install:

```dotenv
SILO_METRICS_LISTEN=127.0.0.1:9091
SILO_DEBUG_LISTEN=127.0.0.1:6060
```

Inside a container, `127.0.0.1` is the container's own loopback. Only
commands run inside the container (`docker compose exec`) can reach these
addresses, which is enough for everything in this file except Prometheus (see
"Keep a history").

Do not add a port mapping for either listener, and never route them through a
reverse proxy.

### Docker Compose

The Compose file from the Silo repository loads `.env` into the `silo`
service. Confirm it does, and that the settings are not already there:

```sh
grep -n 'env_file' docker-compose.yml
grep -nE '^SILO_(METRICS|DEBUG)_LISTEN=' .env
```

Then append the settings and recreate the container. `docker compose restart`
does not re-read `.env`; `up -d` does.

```sh
printf '\n%s\n%s\n' 'SILO_METRICS_LISTEN=127.0.0.1:9091' 'SILO_DEBUG_LISTEN=127.0.0.1:6060' >> .env
docker compose up -d silo
```

If the Compose file has no `env_file` for `silo`, add the two variables under
that service's `environment:` instead.

Undo: delete the two lines from `.env` and run `docker compose up -d silo`.

### Unraid

In the Docker tab, edit the Silo container. Use **Add another Path, Port,
Variable, Label or Device**, choose **Variable**, and add
`SILO_METRICS_LISTEN` = `127.0.0.1:9091`. Repeat for `SILO_DEBUG_LISTEN` =
`127.0.0.1:6060`. **Apply** recreates the container. Do not add a Port entry.
Do not read the template XML to check the result (safety rule 5); check the
log line below instead.

### Plain Docker, Kubernetes, and multiple nodes

- Plain `docker run`: the container must be recreated with
  `-e SILO_METRICS_LISTEN=127.0.0.1:9091 -e SILO_DEBUG_LISTEN=127.0.0.1:6060`
  added and no new `-p`. Ask the user for their run command or script; do not
  reconstruct it with `docker inspect`, which prints secrets.
- Kubernetes: add the variables to the container's `env`. Do not add them to a
  Service or Ingress.
- Separate `proxy` or `transcode` nodes have their own listeners. Enable them
  on the node that shows the problem.

### Check it worked

```sh
curl -fsS http://localhost:8090/api/v1/health
docker compose logs --no-log-prefix silo 2>&1 | grep -E 'metrics listener enabled|local profiling listener' | tail -n 2
docker compose exec -T silo curl -fsS http://127.0.0.1:9091/metrics | grep -c '^silo_'
```

What can go wrong:

- **Silo exits at startup** with `metrics listener: ...` if the metrics
  address is malformed or its port is taken. A `SILO_DEBUG_LISTEN` that is
  not a literal loopback IP and port (a hostname, `0.0.0.0`, port `0`) also
  stops startup. Remove the line and recreate the container.
- **Profiler port taken**: Silo logs `local profiling listener unavailable`
  and keeps running without it.
- **No log line and no metrics**: the running build predates these listeners
  (they arrived in mid-September 2026 builds). Upgrading is a separate
  decision; see `upgrades-and-rollback.md`.

## Reading metrics without Prometheus

A single scrape shows the current state. Take two a few minutes apart to see
what is growing. Filter rather than dumping the whole page into the
conversation:

```sh
docker compose exec -T silo curl -fsS http://127.0.0.1:9091/metrics \
  | grep -E '^(silo_cgroup_|process_resident_memory_bytes|go_goroutines|silo_postgres_pool_connections|silo_queue_)'
```

| Question | Metrics |
|---|---|
| Is memory growing, or is it being killed? | `silo_cgroup_memory_current_bytes` against `silo_cgroup_memory_limit_bytes`, `silo_cgroup_memory_oom_kills_total`, `process_resident_memory_bytes`, `go_memstats_heap_inuse_bytes`, `silo_resource_children_*` |
| Is CPU saturated or throttled? | `process_cpu_seconds_total`, `silo_cgroup_cpu_throttled_periods_total` against `silo_cgroup_cpu_periods_total`, `silo_subprocess_cpu_seconds_total` (FFmpeg and other children) |
| Slow pages while CPU is idle? | `silo_postgres_pool_connections` (`acquired` against `maximum`), `silo_redis_pool_wait_seconds`, `silo_dependency_duration_seconds` |
| Is background work stuck? | `silo_queue_items`, `silo_queue_oldest_requested_timestamp_seconds`, `silo_work_active`, `silo_work_last_progress_timestamp_seconds` |
| Playback slow to start or dropping? | `silo_playback_first_frame_seconds`, `silo_playback_routing_decisions_total`, `silo_direct_stream_*`, `silo_subprocess_exits_total`, `silo_subprocess_peak_rss_bytes` |
| Something leaking? | `go_goroutines` rising steadily while load stays flat |
| Disk filling? | `silo_resource_disk_*` |

A missing value does not mean zero. Check `silo_resource_sample_available`,
`silo_resource_sample_stale`, `silo_resource_source_available`, and
`silo_queue_sample_available` before reading anything into an absent series.
The upstream monitoring guide has a table of symptoms and what to check next.

## Keep a history with Prometheus (optional)

For a problem that shows up every few days, a stored history is what catches
it. Offer this only if the user wants to run Prometheus; it is another service
to maintain. The Silo repository ships ready-made files in
`deploy/observability/`: `prometheus.yml`, alert rules in `silo.rules.yml`,
and `grafana-dashboard.json`.

Prometheus in another container cannot reach the container's `127.0.0.1`, so
the metrics listener has to bind to the container's network interface:
`SILO_METRICS_LISTEN=0.0.0.0:9091`. Without a port mapping, that address is
reachable only from containers on the same Compose network. This is the only
case where the metrics address should be anything other than loopback.

Put the Prometheus service in `docker-compose.override.yml` next to the main
Compose file, so Silo updates to `docker-compose.yml` do not conflict. Compose
merges the override file automatically, unless the user runs Compose with
`-f`; in that case they add it with another `-f`. Check whether an override
file already exists before writing one.

```yaml
services:
  prometheus:
    image: prom/prometheus:v3.5.0
    restart: unless-stopped
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.retention.time=30d
    volumes:
      - ./observability:/etc/prometheus:ro
      - prometheus-data:/prometheus
    ports:
      - "127.0.0.1:9090:9090"
volumes:
  prometheus-data:
```

Get the config and rules from the Silo repository into `./observability/`:

```sh
mkdir -p observability
curl -fsSL -o observability/prometheus.yml https://raw.githubusercontent.com/Silo-Server/silo-server/main/deploy/observability/prometheus.yml
curl -fsSL -o observability/silo.rules.yml https://raw.githubusercontent.com/Silo-Server/silo-server/main/deploy/observability/silo.rules.yml
```

Edit `observability/prometheus.yml` before starting it. The example targets
`silo-api:8080` and `silo-worker:8080`; the main port does not serve metrics.
For a single-host install, keep one target, `silo:9091`, with labels
`cluster: home` and `process_role: integrated`. Never add the profiler port.
Check the file before starting Prometheus:

```sh
docker run --rm --entrypoint promtool -v "$PWD/observability:/etc/prometheus:ro" prom/prometheus:v3.5.0 check config /etc/prometheus/prometheus.yml
docker compose up -d silo prometheus
```

Prometheus is then at `http://127.0.0.1:9090` on the Silo host; from another
machine, use an SSH tunnel (`ssh -L 9090:127.0.0.1:9090 user@host`) rather
than publishing it. Its **Status > Targets** page should show the Silo target
as up. For dashboards, the user can import `grafana-dashboard.json` into a
Grafana they run and choose this Prometheus as its data source.

Undo: `docker compose rm -sf prometheus`, delete the override entries, set
`SILO_METRICS_LISTEN` back to `127.0.0.1:9091`, and recreate `silo`. Removing
the `prometheus-data` volume deletes the stored history; that is the user's
command to run (safety rule 4).

## Profiles

Take profiles when the evidence points at Silo's own process: the `silo`
process (not FFmpeg) using the CPU, Go heap or goroutine counts growing, or
the server hanging while the container stays up. Profiles do not cover FFmpeg,
libvips image processing, plugins, or GPU memory; compare against container
memory and `silo_subprocess_*` metrics for those.

Take captures while the problem is happening. For slow growth, take one early
and one later, and compare.

Profiles contain file paths, stack traces, and symbols. Keep them in a private
directory, never attach them to a public issue or Discord post, and have the
user delete them once the investigation is over.

### Readable without Go tools

The goroutine dump in text form shows what every part of Silo is doing, with
identical stacks grouped and counted. It is the best first capture for hangs
and leaks:

```sh
mkdir -m 700 incident
docker compose exec -T silo curl -fsS 'http://127.0.0.1:6060/debug/pprof/goroutine?debug=1' > incident/goroutines.txt
head -n 200 incident/goroutines.txt
```

Read the largest groups first. A group that grows between two dumps, or many
goroutines waiting on the same lock or network call, is the lead to follow.
The index at `/debug/pprof/` lists what is available.

### Binary captures

Silo's helper script streams captures to private files, caps their size, and
writes a JSON sidecar that records whether the capture is complete. It needs
Node, which is already inside the Silo image. Use `scripts/silo-profile` from
a Silo repository checkout, or download it:

```sh
curl -fsSL -o incident/silo-profile https://raw.githubusercontent.com/Silo-Server/silo-server/main/scripts/silo-profile
docker compose exec -T silo sh -c 'umask 077; mkdir -p /tmp/silo-incident'
docker compose exec -T silo node - --profile cpu --seconds 30 --output /tmp/silo-incident/cpu.pprof < incident/silo-profile
docker compose exec -T silo node - --profile heap --gc 1 --output /tmp/silo-incident/heap.pprof < incident/silo-profile
docker compose cp silo:/tmp/silo-incident/. incident/
docker compose exec -T silo sh -c 'cat "$(command -v silo)"' > incident/silo
chmod 600 incident/silo
```

Other profiles: `allocs` (allocation churn, `--seconds` up to 60),
`goroutine`, and `trace` (`--seconds` up to 5, add
`--max-bytes 67108864`). Only one capture runs at a time; a second gets HTTP
429. Use a capture only if its `.json` sidecar says `"valid": true`. A file
left with a `.partial` name is incomplete.

The copied `silo` binary matches the running build and supplies symbols. If
the user has Go installed, analyse with the Go version recorded in the
sidecar:

```sh
go tool pprof -top incident/silo incident/cpu.pprof
go tool pprof -sample_index=inuse_space -top incident/silo incident/heap.pprof
go tool pprof -diff_base=incident/heap-before.pprof -sample_index=inuse_space -top incident/silo incident/heap-after.pprof
```

Do not install Go without asking. Without it, rely on the text goroutine dump
and metrics. If a Silo maintainer asks for the binary captures, the user can
share them privately; the public report should name the metrics and
summarise what the captures showed.

### Lock contention

Only if goroutine dumps show many goroutines blocked on locks: add
`SILO_DEBUG_BLOCK_RATE=10000000` and `SILO_DEBUG_MUTEX_FRACTION=100`, recreate
the container, capture `block` and `mutex` profiles, then remove both lines
and recreate again. Both need `SILO_DEBUG_LISTEN`. Until they are set, those
profiles return HTTP 409, which says nothing about whether contention exists.

## Leaving them on

A metrics listener on loopback or an internal Compose network is safe to leave
on, and it has to stay on for Prometheus. The profiler is idle until used and
reachable only from inside the container; leaving it on means the next
investigation needs no restart. Either way, it is the user's choice. To turn
one off, remove its line and recreate the container.

At close-out, remind the user to delete `incident/` once they no longer need
it. The copy under `/tmp/silo-incident` in the container disappears when the
container is recreated.
