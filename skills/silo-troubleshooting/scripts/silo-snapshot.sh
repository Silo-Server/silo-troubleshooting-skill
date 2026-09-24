#!/usr/bin/env bash
# Read-only snapshot of a Silo deployment for troubleshooting.
#
# It never changes anything: no restarts, no writes, no database changes.
# It never prints SECRET_KEY, passwords, or the container environment.
#
# Usage:
#   silo-snapshot.sh                      # Docker Compose; run from the directory with docker-compose.yml
#   silo-snapshot.sh --container Silo     # plain Docker / Unraid; give the Silo container name
#   silo-snapshot.sh --port 8090          # host port for the health checks (default: PORT from .env, else 8090)
#   silo-snapshot.sh --lines 300          # how many recent log lines to show errors from (default 400)
#   silo-snapshot.sh --since 24h          # window for the message-frequency summary (default 6h)
#
# On another machine, pipe it over SSH (the script reads nothing else from stdin):
#   ssh user@host 'cd /path/to/compose/dir && bash -s -- --since 24h' < silo-snapshot.sh

set -u

container=""
port=""
lines=400
since=6h

while [ $# -gt 0 ]; do
  case "$1" in
    --container|--port|--lines|--since)
      if [ $# -lt 2 ] || [ -z "$2" ]; then echo "$1 needs a value" >&2; exit 2; fi ;;
  esac
  case "$1" in
    --container) container="$2"; shift 2 ;;
    --port) port="$2"; shift 2 ;;
    --lines) lines="$2"; shift 2 ;;
    --since) since="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

section() { printf '\n===== %s =====\n' "$1"; }

# Mask credentials that can appear in log lines. Silo already redacts known
# secret fields before logging; this is a second net, not a guarantee.
redact() {
  sed -E \
    -e 's#(postgres(ql)?|rediss?)://[^@/[:space:]]+@#\1://[REDACTED]@#g' \
    -e 's#([Bb][Ee][Aa][Rr][Ee][Rr] )[A-Za-z0-9._~+/=-]+#\1[REDACTED]#g' \
    -e 's#sa_[A-Za-z0-9_-]{8,}#sa_[REDACTED]#g' \
    -e 's#([A-Za-z_-]*([Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Tt][Oo][Kk][Ee][Nn]|[Aa][Pp][Ii]_?[Kk][Ee][Yy])[A-Za-z_-]*=)("?)[^[:space:]",&]+#\1\3[REDACTED]#g' \
    -e 's#([A-Za-z_-]*([Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Tt][Oo][Kk][Ee][Nn]|[Aa][Pp][Ii]_?[Kk][Ee][Yy])[A-Za-z_-]*"[[:space:]]*:[[:space:]]*")[^"]+#\1[REDACTED]#g'
}

# Read one non-secret key from .env without sourcing the file.
env_value() {
  [ -f .env ] || return 0
  grep -E "^[[:space:]]*$1=" .env | tail -n 1 | cut -d= -f2- | sed -E 's/^["'\'']//; s/["'\'']$//'
}

have() { command -v "$1" >/dev/null 2>&1; }

if ! have docker; then
  echo "docker is not installed or not on PATH; this script only covers Docker deployments." >&2
  exit 1
fi

mode="compose"
if [ -n "$container" ]; then
  mode="docker"
else
  compose_out="$(docker compose ps -a -q silo 2>&1)"
  compose_rc=$?
  if [ "$compose_rc" -ne 0 ] || [ -z "$compose_out" ]; then
    if [ "$compose_rc" -ne 0 ]; then
      echo "docker compose reported:" >&2
      printf '%s\n' "$compose_out" | redact | sed 's/^/  /' >&2
    fi
    echo "No Compose service named 'silo' found from this directory." >&2
    echo "Run this from the directory that holds docker-compose.yml, or pass --container <name>." >&2
    echo "Containers that look like Silo:" >&2
    docker ps -a --format '  {{.Names}}  {{.Image}}  {{.Status}}' | grep -i silo >&2 || true
    exit 1
  fi
fi

silo_exec() {
  # </dev/null: when this script is piped to `bash -s`, exec would otherwise
  # swallow the rest of the script from stdin.
  if [ "$mode" = compose ]; then docker compose exec -T silo "$@" </dev/null; else docker exec "$container" "$@" </dev/null; fi
}
silo_logs() {
  if [ "$mode" = compose ]; then docker compose logs --no-color "$@" silo 2>&1; else docker logs "$@" "$container" 2>&1; fi
}

[ -n "$port" ] || port="$(env_value PORT)"
[ -n "$port" ] || port=8090

section "When and where"
date -u '+%Y-%m-%dT%H:%M:%SZ'
uname -srm
docker version --format 'docker client {{.Client.Version}}, server {{.Server.Version}}' 2>/dev/null
[ "$mode" = compose ] && docker compose version 2>/dev/null

section "Compose file check"
if [ "$mode" = compose ]; then
  # --quiet prints only errors, never the resolved configuration (which holds secrets).
  if config_err="$(docker compose config --quiet 2>&1)"; then
    echo "compose configuration is valid"
  else
    printf '%s\n' "$config_err" | redact
  fi
else
  echo "(skipped: plain Docker mode)"
fi

section "Containers"
if [ "$mode" = compose ]; then
  docker compose ps -a --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}' 2>/dev/null || docker compose ps -a
else
  docker ps -a --filter "name=^/${container}$" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
fi

section "Silo container state and image"
cid="$container"
[ "$mode" = compose ] && cid="$(docker compose ps -a -q silo 2>/dev/null)"
if [ -n "$cid" ]; then
  docker inspect --format 'restarts={{.RestartCount}} oom_killed={{.State.OOMKilled}} exit_code={{.State.ExitCode}} started={{.State.StartedAt}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid"
  image_id="$(docker inspect --format '{{.Image}}' "$cid" 2>/dev/null)"
  [ -n "$image_id" ] && docker image inspect --format 'image digest: {{join .RepoDigests " "}}' "$image_id" 2>/dev/null
fi

section "Non-secret settings from .env"
if [ "$mode" = compose ] && [ -f .env ]; then
  for k in SILO_IMAGE MEDIA_ROOT MEDIA_CONTAINER_ROOT SILO_DATA_ROOT PORT JF_PORT ABS_PORT COMPOSE_FILE POSTGRES_TUNE SILO_MIGRATE_TIMEOUT; do
    v="$(env_value "$k")"
    [ -n "$v" ] && echo "$k=$v"
  done
  if grep -qE '^[[:space:]]*SECRET_KEY=.+' .env; then echo "SECRET_KEY is set (value not shown)"; else echo "SECRET_KEY is NOT set in .env"; fi
else
  echo "(skipped: no .env in this directory, or plain Docker mode)"
fi

section "Health and readiness on port $port"
if have curl; then
  printf 'health: '; curl -sS -m 5 "http://localhost:${port}/api/v1/health" || echo "(no response)"; echo
  printf 'ready:  '; curl -sS -m 5 "http://localhost:${port}/api/v1/ready" || echo "(no response)"; echo
else
  echo "curl not installed on the host; skipped"
fi

section "PostgreSQL and Redis"
if [ "$mode" = compose ]; then
  if [ -n "$(docker compose ps -q postgres 2>/dev/null)" ]; then
    docker compose exec -T postgres pg_isready </dev/null 2>&1
  else
    echo "no running bundled postgres service (external database, or it is stopped)"
  fi
  if [ -n "$(docker compose ps -q redis 2>/dev/null)" ]; then
    printf 'redis: '; docker compose exec -T redis redis-cli ping </dev/null 2>&1
  else
    echo "no running bundled redis service (external Redis, or it is stopped)"
  fi
else
  if docker ps --format '{{.Names}}' | grep -qx 'Silo-PostgreSQL'; then
    docker exec Silo-PostgreSQL pg_isready </dev/null 2>&1
  else
    echo "no running container named Silo-PostgreSQL; check the database container by hand"
  fi
  echo "Redis: check it with: docker exec <redis-container> redis-cli ping"
fi

section "Inside the Silo container"
media_root="$(env_value MEDIA_CONTAINER_ROOT)"
# shellcheck disable=SC2016 # expanded by the container's shell, not this one
silo_exec env SNAP_MEDIA="$media_root" sh -c '
  echo "media mounts:"
  for d in ${SNAP_MEDIA:-} /mnt/media /mnt/user/data; do
    [ -d "$d" ] || continue
    out=$(ls "$d" 2>&1 | head -n 20 | tr "\n" " ")
    echo "  $d: ${out:-(empty)}"
  done
  echo "GPU devices:"; ls -l /dev/dri 2>/dev/null || echo "  /dev/dri not present (no VA-API/QSV)"
  command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=name,driver_version,utilization.gpu --format=csv,noheader 2>&1 | sed "s/^/  nvidia: /"
  ff=/usr/lib/jellyfin-ffmpeg/ffmpeg
  [ -x "$ff" ] || ff=$(command -v ffmpeg 2>/dev/null)
  echo "ffmpeg:"
  if [ -n "$ff" ]; then "$ff" -hide_banner -version 2>&1 | head -n 1 | sed "s/^/  /"; else echo "  ffmpeg not found"; fi
  echo "disk:"
  for d in /var/lib/silo/artwork /var/lib/silo/plugins /var/lib/silo /tmp/silo-transcode; do
    [ -d "$d" ] && df -h "$d" 2>/dev/null | tail -n 1 | sed "s#^#  $d: #"
  done
' 2>&1

section "Resource use"
if [ "$mode" = compose ]; then
  # shellcheck disable=SC2046 # one argument per container ID
  docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' $(docker compose ps -q) 2>/dev/null
else
  docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' "$container" 2>/dev/null
fi

section "Most frequent warning and error messages, last $since"
# Works for both text (level=WARN msg="...") and JSON ("level":"WARN","msg":"...") logs.
silo_logs --since "$since" \
  | grep -E 'level=(WARN|ERROR)|"level":"(WARN|ERROR)"' \
  | sed -nE 's/.*level=(WARN|ERROR).* msg=("[^"]*"|[^ ]+).*/\1 \2/p; s/.*"level":"(WARN|ERROR)".*"msg":("[^"]*").*/\1 \2/p' \
  | sort | uniq -c | sort -rn | head -n 25 | redact
echo "(counts; drill into one with: docker compose logs --since $since silo | grep -F '<message>')"

section "Warnings and errors in the last $lines log lines (redacted)"
silo_logs --tail "$lines" | grep -iE 'level=(warn|error)|"level":"(warn|error)"|fatal|panic|failed|unreachable|refus|denied|required|bootstrap:|database pool:|loading settings:|log stream hub' | redact | tail -n 80

section "Last 30 log lines (redacted)"
silo_logs --tail 30 | redact

echo
echo "Snapshot finished. Review it for anything private before sharing it outside this machine."
