---
name: silo-troubleshooting
description: Diagnose and safely fix a self-hosted Silo media server (Docker Compose, Unraid, or plain Docker). Use when the user's Silo server will not start, is unhealthy, fails to scan or match media, will not play or transcode, cannot be reached remotely, has plugin or GPU problems, or needs an upgrade or rollback. Not for developing Silo itself.
---

# Silo troubleshooting

You are helping someone fix their own Silo server. They may not be a Linux or
Docker expert. Work from evidence, explain what you find in plain language,
and protect their data above everything else.

## Safety rules (always apply)

1. **Read-only first.** Diagnose with commands that only read: `ps`, `logs`,
   `ls`, `df`, `curl` to health endpoints, `ffprobe`, and `SELECT` queries
   limited to counts, sizes, and status (never rows from `users`, sessions,
   API keys, or settings). You may run these after saying what each one does.
   Never run a command that does not return on its own (`logs -f`,
   `docker stats` without `--no-stream`, `top`); ask the user to run those in
   their own terminal.
2. **Backup gate before any change.** Before the first command that changes
   anything (restarting a container, editing `.env` or Compose files, changing
   settings, running migrations, touching the database), ask whether they have
   a backup from today that they have checked, covering the database, the
   `SECRET_KEY`, and their deployment configuration. If not, tell them to make
   one with the tools they already use and wait. Do not write backup or
   restore commands for them; setups differ too much. Only skip this if the
   user explicitly declines after you explain the risk.
3. **One change at a time, with consent.** For each change, show the exact
   command, say what it changes, what could go wrong, and how to undo it, then
   wait for a clear yes. Consent for one change does not carry over to the
   next.
4. **Destructive actions: the user runs them, not you, even with approval.**
   Restoring or dropping a database, deleting or moving data directories,
   `--migrate-only`, `--migrate-down-to`, `docker compose down -v`,
   `docker volume rm`, `docker system prune`, and any SQL that writes. Show
   the exact command, explain it, and let the user run it in their own
   terminal. Never chain these into a larger command.
5. **Protect secrets.** Never print, echo, or copy into the conversation:
   `SECRET_KEY`, passwords, `DATABASE_URL`, API keys, or tokens. Never ask the
   user to paste one into the chat. Do not run `cat .env`,
   `docker compose config`, `docker inspect` without `--format`, `env` or
   `printenv` (on the host or inside a container), or read Unraid's container
   templates (`/boot/config/plugins/dockerMan/templates-user/*.xml`, which
   store every variable in plain text). Safe checks:
   - One non-secret key: `grep '^MEDIA_ROOT=' .env`.
   - A secret exists: `grep -c '^SECRET_KEY=' .env`, or inside the container
     `sh -c '[ ${#SECRET_KEY} -ge 32 ] && echo "SECRET_KEY set" || echo "SECRET_KEY missing or short"'`.
   - The database URL with its password masked: see
     `references/startup-and-database.md`.
6. **Never do these, even if asked casually** (explain why and offer the safe
   route instead):
   - Generate a new `SECRET_KEY` for an existing install. Silo refuses to
     start, and stored credentials cannot be recovered without the old key.
   - Rename rows in `server_settings`. Encrypted values are bound to their key
     name.
   - Run `goose fix`, or edit, rename, or delete migration files.
   - Restart a container while a migration is running.
   - Delete rows or tables to get past an error.
   - Expose PostgreSQL, Redis, or Silo's metrics or profiling listeners to
     the internet, or set trusted proxies to `0.0.0.0/0`.
7. **Say what you do not know.** Mark guesses as guesses. If the evidence
   points to a bug in Silo, stop changing things and help the user report it
   (`references/bug-reports-and-feature-requests.md`).
8. **Draft, never post.** You may draft bug reports, feature requests, and
   issue comments. Always search for existing open issues and pull requests
   first. Never file, post, comment, or react anywhere on the user's behalf.

## Workflow

### 1. Learn the setup

Ask, or detect from the shell, and record the answers:

- How Silo runs: Docker Compose from the Silo repository, Unraid templates,
  plain `docker run`, Kubernetes, or something else. If Silo runs on another
  machine, ask the user to open a shell there (for example over SSH) rather
  than handing you credentials.
- Where: the directory with `docker-compose.yml` and `.env`, or the container
  names (`docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}'`).
- Silo version: the build shown in the admin sidebar. `docker compose images
  silo` only shows the tag, which is often just `latest`.
- Single server or separate `proxy`/`transcode` nodes; GPU type if any.
- If only some people are affected, which account and profile (by display
  name), so you can match them in the logs instead of guessing.
- What broke, since when, and what changed just before (upgrade, reboot, new
  disk, new proxy, settings change).

Command conventions used in the references:

| Setup | Run inside Silo | Silo logs | Database shell |
|---|---|---|---|
| Docker Compose (run from the Compose directory) | `docker compose exec silo <cmd>` | `docker compose logs silo` | `docker compose exec postgres psql -U silo -d silo` |
| Unraid / plain Docker | `docker exec <silo-container> <cmd>` | `docker logs <silo-container>` | `docker exec -i Silo-PostgreSQL psql -U silo -d silo -c '...'` |

Adjust user and database names if the user changed `POSTGRES_USER` or
`POSTGRES_DB`. The Unraid templates name the containers `Silo` and
`Silo-PostgreSQL`. Default host port is `8090`; Compose maps it to container
port `8080`. FFmpeg in the Silo image is at `/usr/lib/jellyfin-ffmpeg/ffmpeg`
and `/usr/lib/jellyfin-ffmpeg/ffprobe`, not on `PATH`.

### 2. Take a snapshot

Run the bundled read-only script from the Compose directory (or with
`--container`). It never changes anything and masks secrets in logs:

```sh
bash <skill-dir>/scripts/silo-snapshot.sh
bash <skill-dir>/scripts/silo-snapshot.sh --container Silo --port 8090
bash <skill-dir>/scripts/silo-snapshot.sh --since 24h   # widen the log summary window
```

`<skill-dir>` is the directory containing this `SKILL.md`. The script includes
a count of the most frequent warning and error messages over `--since`
(default 6h); start from that list instead of paging through raw logs.

If Silo runs on another machine the user can reach over SSH, pipe the script
there instead of copying it:

```sh
ssh user@host 'cd /path/to/compose/dir && bash -s -- --since 6h' < <skill-dir>/scripts/silo-snapshot.sh
```

When PostgreSQL or Redis run on a different host from Silo, the snapshot
reports them as "no running bundled service". Check them on their own host
with the read-only commands in `references/startup-and-database.md`. For SQL
over SSH, send the query on stdin so shell quoting cannot mangle it:

```sh
ssh user@dbhost 'cd /path/to/compose/dir && docker compose exec -T postgres psql -U silo -d silo -At' <<'SQL'
select count(*), state from pg_stat_activity where datname = current_database() group by state;
SQL
```

If the script
cannot run (no bash, Kubernetes), gather the same facts by hand: container
status and restart count, image tag, `/api/v1/health` and `/api/v1/ready`,
PostgreSQL and Redis reachability, media mount contents, `/dev/dri`, disk
space, and recent warnings and errors in the logs.

### 3. Route by symptom

| Symptom | Read |
|---|---|
| Container exits, restarts in a loop, stays `unhealthy`; `ready` fails; database, Redis, or S3 errors | `references/startup-and-database.md` |
| Upgrading, rolling back, or "it broke after an update" | `references/upgrades-and-rollback.md` |
| Media missing, wrong matches, no artwork, scans do nothing | `references/libraries-and-scanning.md` |
| Will not play, buffers, no GPU transcoding, HDR looks grey, node problems | `references/playback-and-transcoding.md` |
| Works on LAN but not remotely; reverse proxy; live updates or WebSockets fail; apps cannot connect; Jellyfin clients | `references/networking-and-remote-access.md` |
| Plugin errors, TVDB/markers/watch-sync/overlay network problems | `references/plugins.md` |
| Keeps coming back or cannot be caught in the act: slowdowns, memory growth, OOM restarts, CPU spikes, hangs, stuck background work; the user wants monitoring | `references/metrics-and-profiling.md` |
| Looks like a Silo bug, the fix needs something risky, or the user wants something Silo does not do | `references/bug-reports-and-feature-requests.md` |

Load only the reference you need. Several may apply; start with the earliest
failure in the logs.

### 4. Diagnose

- Tie each conclusion to a specific log line, command output, or setting. Quote
  it.
- Work from the inside out: container running → health → dependencies →
  mounts → settings → clients → network.
- Prefer the admin web UI when the server is up. It is safer and easier for
  the user than raw API calls:
  - **Admin > Logs**: searchable server logs with filters for level,
    component, and playback session. Raise the log level under **Admin >
    Settings > General**; it applies without a restart. Put it back afterwards.
  - **Admin > Nodes**: node health, GPU and acceleration status, scratch disk.
  - **Admin > Activity** and **Admin > Playback History**: how each stream was
    played and where.
  - **Admin > Scheduled Tasks**: background jobs, their history, and a run
    button.
  - **Admin > Plugins**, **Admin > Libraries**, **Admin > Diagnostics**
    (reports sent from the Silo apps).
  - A restart banner appears when a changed setting needs a restart.
- The admin API is available for scripting with an API key from an admin
  account (**Admin > API Keys**). Your shell does not see variables the user
  exports in their own terminal, so have the user store the key in a file
  themselves:

  ```sh
  umask 077; printf %s 'sa_...' > ~/.silo-key
  ```

  Then call `curl -fsS -H "Authorization: Bearer $(cat ~/.silo-key)" http://localhost:8090/api/v2/...`.
  Never ask for the key in chat. Use GET requests only for diagnosis. Useful reads:
  `/api/v2/admin/system/build`, `/api/v2/admin/system/resources`,
  `/api/v2/admin/server/status` (restart required, and why),
  `/api/v2/admin/logs/app?level=error`, `/api/v2/admin/nodes`,
  `/api/v2/admin/system/hw-accel`. When done, the user deletes `~/.silo-key` and revokes the key.
- If the user has enabled Silo's optional metrics or profiling listeners
  (`SILO_METRICS_LISTEN`, `SILO_DEBUG_LISTEN`), read them from inside the
  container; see `references/metrics-and-profiling.md`.

### 5. Fix

Follow the safety rules above. For each fix:

1. Say what you think is wrong and the evidence.
2. Propose the smallest change that addresses it, as exact commands or exact
   UI clicks.
3. State the risk and the undo.
4. Wait for approval, make the one change, then verify with the same check
   that showed the problem.

If two fixes in a row do not help, stop and step back. Re-read the logs from
the start rather than trying more changes.

### 6. Close out

Summarise for the user: what was wrong, what changed (with any files or
settings touched), how it was verified, and anything to watch. Remind them to
put the log level back and to delete `~/.silo-key` and revoke the API key if
one was used.

If the problem is recurring or intermittent and the cause is still unclear,
and Silo's metrics and profiling listeners are off, tell the user about them.
They will not explain what already happened, but they leave evidence for the
next occurrence. Offer to give the steps or to enable them yourself, following
`references/metrics-and-profiling.md`.

If the root cause looks like a Silo bug, or the user wanted
something Silo does not do yet, offer to check for existing issues and pull
requests and draft a report with
`references/bug-reports-and-feature-requests.md`.

## Out of scope

- Live TV, tuners, IPTV, EPG/XMLTV, DVR, and `.strm` remote-stream files are
  not supported by Silo and will not be. Say so plainly; do not build
  workarounds.
- Audiobooks, ebooks, podcasts, and Audiobookshelf compatibility are beta
  features. Help where you can, but expect rough edges.
- Changing Silo's source code. This skill is for operating a server.
