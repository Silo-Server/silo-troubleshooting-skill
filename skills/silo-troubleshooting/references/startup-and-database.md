# Startup failures, database, Redis, and storage

Use this when the Silo container exits, restarts in a loop, stays
`unhealthy`, or `/api/v1/ready` fails.

## First look

```sh
docker compose ps -a
docker compose logs --tail 200 silo
docker compose logs --tail 50 postgres
docker compose logs --tail 50 redis
```

Plain Docker or Unraid: `docker ps -a`, then `docker logs --tail 200 <silo-container>`.

Never run `logs -f` (follow) from the agent's shell; it never returns. Use
`--since 5m` and repeat, or ask the user to run
`docker compose logs -f silo` in their own terminal.

Read from the **first** error, not the last. A restart loop repeats the same
failure; find the line with a fatal message.

## What stops Silo from starting

| Message (after the timestamp) | Meaning | Safe fix |
|---|---|---|
| Compose: `required variable SECRET_KEY is missing a value` or `required variable MEDIA_ROOT is missing a value` | `.env` lacks the variable, or Compose is run from the wrong directory | Run from the directory with `.env`. New install: add the value. Existing install: restore the original `SECRET_KEY` from backup. |
| `Bind for 0.0.0.0:8096 failed: port is already allocated` (or 8090, 13378) | Another program (often Jellyfin) uses the port | Stop the other program, or change `PORT`/`JF_PORT`/`ABS_PORT` in `.env`. |
| `bootstrap: DATABASE_URL is required (set in .env or environment)` | No database URL (Unraid, custom Compose) | Set it. Compose sets it for the bundled database. |
| `bootstrap: SECRET_KEY is required (>=32 chars); generate one with: openssl rand -base64 48` | Key missing or shorter than 32 characters | New install: generate one. **Existing install: restore the original key. Never generate a new one.** |
| `loading settings: decrypt setting "...": secret: authenticate ciphertext: ...` | `SECRET_KEY` does not match this database (key changed, or a dump restored with a different key) | Put back the key this database was created with. Never delete or rename the setting rows. |
| `database pool: ...` | Wrong host, password, or database name; PostgreSQL not ready | See "Check the database URL safely" below, then the PostgreSQL logs. |
| `failed to run migrations: ...` | A migration failed or timed out | See "Migration failures". Do not keep restarting. |
| `log stream hub start: ...` (often `connection refused`) | Redis is unreachable | Check `REDIS_URL` and that Redis runs. Needed in every mode. |
| `redis is required for this mode` | `REDIS_URL` missing or malformed on a proxy/transcode node | Fix `REDIS_URL`. |
| `invalid SILO_TRUSTED_PROXIES: ...` | Malformed CIDR list in the environment | Fix or remove the variable. |
| `preload enabled plugins: ...` | An enabled plugin could not be loaded | See `plugins.md`. |

On a successful start the log shows `connected to PostgreSQL`, then
migration output, then the HTTP listeners.

On Unraid, PostgreSQL and Redis must be running before Silo starts. Silo stops
if either is unavailable. Put them ahead of Silo in the autostart order with a
short wait after PostgreSQL.

## Check the database URL safely

Never print `DATABASE_URL` as-is; it contains the password. Show it with the
password masked:

```sh
docker compose exec -T silo sh -c 'echo "$DATABASE_URL" | sed -E "s#://([^:@/]+):[^@]*@#://\1:[REDACTED]@#"'
# Unraid / plain Docker (container must be running):
docker exec Silo sh -c 'echo "$DATABASE_URL" | sed -E "s#://([^:@/]+):[^@]*@#://\1:[REDACTED]@#"'
```

If the container will not stay up, have the user open the setting themselves
(the Compose file or the Unraid template) and check the host, port, and
database name without pasting the password.

Common mistakes:

- On Unraid's default bridge network, containers cannot reach each other by
  name. Use the server's LAN IP, not `postgres`.
- A password with `@`, `:`, `/`, `#`, or `%` must be percent-encoded in the URL.
- The bundled Compose stack hard-codes its own `DATABASE_URL`. Setting one in
  `.env` does not replace it.

## Health and readiness

```sh
curl -fsS http://localhost:8090/api/v1/health   # process is up
curl -fsS http://localhost:8090/api/v1/ready    # plus PostgreSQL (and S3 if configured)
```

- `ready` returns 503 only when PostgreSQL is unreachable.
- `ready` returns 200 with `"status":"degraded"` when artwork or S3 storage
  fails its probe. The server works, but images may be missing.
- The Docker healthcheck calls `/api/v1/health` inside the container on port
  8080.

## Migration failures

- A long migration is not a failure. Silo holds a database lock and does not
  open its HTTP port until migrations finish, so `docker ps` can show
  `unhealthy` while it works. Check progress with
  `docker compose logs --since 5m silo`. **Never restart during a migration.**
- Timeout: migrations stop after 20 minutes by default. The user can set
  `SILO_MIGRATE_TIMEOUT=60m` (or `0` for no limit) and start again.
- Disk: some migrations rewrite whole tables and need free space for a second
  copy. Check `df -h` on the PostgreSQL data path.
- Data-integrity migrations can refuse to apply when they find orphaned rows,
  and roll themselves back. The error names the table. Stop and help the user
  report it (see `reporting-issues.md`). Do not delete rows to get past it.
- To list applied migrations when no migration is running:

  ```sh
  docker compose run --rm --no-deps silo --migrate-status
  ```

  This only lists migrations on an installed database, but it waits behind a
  running migration's lock, so do not use it during an upgrade.

## PostgreSQL checks

These only read:

```sh
docker compose exec postgres pg_isready -U silo
docker compose exec postgres psql -U silo -d silo -c "select version();"
docker compose exec postgres psql -U silo -d silo -c "select count(*) from pg_stat_activity;"
docker compose exec postgres psql -U silo -d silo -c "select pg_size_pretty(pg_database_size(current_database()));"
```

Unraid: `docker exec -i Silo-PostgreSQL psql -U silo -d silo -c "..."`.

Limit queries to counts, sizes, and status. Do not select rows from tables
that hold people's data (`users`, sessions, API keys, settings). Any statement
that writes (`UPDATE`, `DELETE`, `DROP`, `ALTER`, `TRUNCATE`, `INSERT`) is for
the user to run in their own terminal after a verified backup. Show it and
explain it; do not run it.

### PostgreSQL auto-tuning

With `POSTGRES_TUNE=auto` (the Compose default), Silo writes tuning values into
PostgreSQL with `ALTER SYSTEM`. Settings that need a PostgreSQL restart are
logged by name on every Silo start until PostgreSQL restarts. That warning is
harmless. The fix, during a quiet window, is a change that needs approval:

```sh
docker compose restart postgres silo
```

For an external or managed database, set `POSTGRES_TUNE=off`.

## Redis checks

```sh
docker compose exec redis redis-cli ping    # expect PONG
```

Redis holds coordination and cache data, not the catalog. Restarting it does
not lose library data, but it can briefly interrupt playback and live updates,
so pick a quiet moment.

## Artwork and S3 storage

- `blob storage unavailable; readiness will retry` means the artwork store
  failed its startup probe. Check the bucket endpoint, credentials, and clock
  skew, or the local artwork directory's permissions.
- `recorded storage location no longer matches this process` or
  `private storage identity mismatch: ...` means the bucket, endpoint, or path
  was edited on an existing install. Put the old values back. Moving storage
  happens through **Admin > Settings > Storage & Database**.

## Container resources

```sh
docker stats --no-stream
df -h
docker inspect --format 'oom_killed={{.State.OOMKilled}} restarts={{.RestartCount}}' <container>
```

Always pass `--format` to `docker inspect`. Without it, it prints the
container's environment, including secrets.
