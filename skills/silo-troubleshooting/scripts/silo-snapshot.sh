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
#   silo-snapshot.sh --lines 300          # how many recent log lines to scan (default 400)

set -u

container=""
port=""
lines=400

while [ $# -gt 0 ]; do
  case "$1" in
    --container) container="${2:-}"; shift 2 ;;
    --port) port="${2:-}"; shift 2 ;;
    --lines) lines="${2:-400}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

section() { printf '\n===== %s =====\n' "$1"; }

# Mask credentials that can appear in log lines.
redact() {
  sed -E \
    -e 's#(postgres(ql)?|redis|rediss)://[^@/[:space:]]+@#\1://[REDACTED]@#g' \
    -e 's#([Bb]earer )[A-Za-z0-9._~+/=-]+#\1[REDACTED]#g' \
    -e 's#sa_[A-Za-z0-9_-]{8,}#sa_[REDACTED]#g' \
    -e 's#((SECRET_KEY|PASSWORD|TOKEN|API_KEY|api_key|password|token|secret)[\"]?[=:][[:space:]]*[\"]?)[^[:space:]\",]+#\1[REDACTED]#g'
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
elif ! docker compose ps >/dev/null 2>&1 || [ -z "$(docker compose ps -a -q silo 2>/dev/null)" ]; then
  echo "No Compose service named 'silo' found in this directory." >&2
  echo "Run this from the directory that holds docker-compose.yml, or pass --container <name>." >&2
  echo "Containers that look like Silo:" >&2
  docker ps -a --format '  {{.Names}}  {{.Image}}  {{.Status}}' | grep -i silo >&2 || true
  exit 1
fi

silo_exec() {
  if [ "$mode" = compose ]; then docker compose exec -T silo "$@"; else docker exec "$container" "$@"; fi
}
silo_logs() {
  if [ "$mode" = compose ]; then docker compose logs --no-color --tail "$lines" silo 2>&1; else docker logs --tail "$lines" "$container" 2>&1; fi
}

[ -n "$port" ] || port="$(env_value PORT)"
[ -n "$port" ] || port=8090

section "When and where"
date -u '+%Y-%m-%dT%H:%M:%SZ'
uname -srm
docker version --format 'docker client {{.Client.Version}}, server {{.Server.Version}}' 2>/dev/null
[ "$mode" = compose ] && docker compose version 2>/dev/null

section "Containers"
if [ "$mode" = compose ]; then
  docker compose ps -a --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}' 2>/dev/null || docker compose ps -a
  echo
  docker compose images silo 2>/dev/null
else
  docker ps -a --filter "name=^/${container}$" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
fi

section "Restart count and OOM kills"
cid="$container"
[ "$mode" = compose ] && cid="$(docker compose ps -a -q silo 2>/dev/null)"
[ -n "$cid" ] && docker inspect --format 'restarts={{.RestartCount}} oom_killed={{.State.OOMKilled}} exit_code={{.State.ExitCode}} started={{.State.StartedAt}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid"

section "Non-secret settings from .env"
if [ "$mode" = compose ] && [ -f .env ]; then
  for k in SILO_IMAGE MEDIA_ROOT MEDIA_CONTAINER_ROOT SILO_DATA_ROOT PORT JF_PORT COMPOSE_FILE POSTGRES_TUNE SILO_MIGRATE_TIMEOUT; do
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

if [ "$mode" = compose ]; then
  section "PostgreSQL and Redis"
  if [ -n "$(docker compose ps -q postgres 2>/dev/null)" ]; then
    docker compose exec -T postgres pg_isready 2>&1
  else
    echo "no bundled postgres service (external database?)"
  fi
  if [ -n "$(docker compose ps -q redis 2>/dev/null)" ]; then
    printf 'redis: '; docker compose exec -T redis redis-cli ping 2>&1
  else
    echo "no bundled redis service (external Redis?)"
  fi
fi

section "Inside the Silo container"
# shellcheck disable=SC2016 # expanded by the container's shell, not this one
silo_exec sh -c '
  echo "media mounts:"; for d in /mnt/media /mnt/user/data; do [ -d "$d" ] && { printf "  %s: " "$d"; out=$(ls "$d" 2>&1 | head -n 20 | tr "\n" " "); echo "${out:-(empty)}"; }; done
  echo "GPU devices:"; ls -l /dev/dri 2>/dev/null || echo "  /dev/dri not present (no VA-API/QSV)"
  command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=name,driver_version,utilization.gpu --format=csv,noheader 2>&1 | sed "s/^/  nvidia: /"
  echo "ffmpeg:"; if command -v ffmpeg >/dev/null 2>&1; then ffmpeg -hide_banner -version 2>&1 | head -n 1; else echo "  ffmpeg not found"; fi
  echo "disk:"; df -h /var/lib/silo /tmp/silo-transcode 2>/dev/null
' 2>&1

section "Resource use"
if [ "$mode" = compose ]; then
  # shellcheck disable=SC2046 # one argument per container ID
  docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' $(docker compose ps -q) 2>/dev/null
else
  docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' "$container" 2>/dev/null
fi

section "Warnings and errors in the last $lines log lines (redacted)"
silo_logs | grep -iE 'level=(warn|error)|"level":"(warn|error)"|fatal|panic|failed|unreachable|refus|denied|required|bootstrap:|database pool:' | redact | tail -n 80

section "Last 30 log lines (redacted)"
silo_logs | tail -n 30 | redact

echo
echo "Snapshot finished. Review it for anything private before sharing it outside this machine."
