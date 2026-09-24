# Startup failures, database, Redis, and storage

Use this when the Silo container exits, restarts in a loop, stays
`unhealthy`, or `/api/v1/ready` fails.

## First look

```sh
docker compose ps
docker compose logs --tail 200 silo
docker compose logs --tail 50 postgres
docker compose logs --tail 50 redis
```

Plain Docker or Unraid: `docker ps -a`, then `docker logs --tail 200 <silo-container>`.

Read from the **first** error, not the last. A restart loop repeats the same
failure; find the line that starts with a fatal message.

## Startup order and what stops it

Silo starts in this order. The first failing step is the one to fix.

| Step | Fatal message (after the timestamp) | Usual cause | Safe fix |
|---|---|---|---|
| Read `.env` / environment | `bootstrap: DATABASE_URL is required (set in .env or environment)` | Missing `DATABASE_URL` (Unraid, custom Compose) | Set it. Compose sets it for the bundled database. |
| Read `SECRET_KEY` | `bootstrap: SECRET_KEY is required (>=32 chars); generate one with: openssl rand -base64 48` | Missing or short key | New install: generate one. **Existing install: restore the original key from backup. Never generate a new one.** |
| Connect to PostgreSQL | `database pool: ...` | Wrong host, password, or database; PostgreSQL not ready | Check `DATABASE_URL`, then the postgres container's logs. On Unraid's default bridge network, use the server's LAN IP, not `postgres`. Percent-encode special characters in the password. |
| Apply migrations | `failed to run migrations: ...` | A migration failed or timed out | See "Migration failures" below. Do not keep restarting. |
| Trusted proxies | `invalid SILO_TRUSTED_PROXIES: ...` | Malformed CIDR list in the environment | Fix or remove the variable. |
| Plugins | `preload enabled plugins: ...` | An enabled plugin could not be loaded | See `plugins.md`. |
| Redis (proxy/transcode nodes) | `redis is required for this mode` | `REDIS_URL` wrong or unreachable | Fix `REDIS_URL`. |

On the main server, Redis problems may not stop startup. They show up later as
errors that mention `redis`. Treat Redis as required on every deployment.

On a successful start the log contains `connected to PostgreSQL`, then
migration output, then the HTTP listeners.

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
  `unhealthy` while it works. Follow `docker compose logs -f silo`.
- Timeout: migrations stop after 20 minutes by default. Set
  `SILO_MIGRATE_TIMEOUT=60m` (or `0`) and start again.
- Disk: some migrations rewrite whole tables and need free space for a second
  copy. Check `df -h` on the PostgreSQL data path.
- Data-integrity migrations can refuse to apply when they find orphaned rows,
  and roll themselves back. The error names the table. Stop and help the user
  report it (see `reporting-issues.md`). Do not delete rows to get past it.
- Check what is applied (read-only):

  ```sh
  docker compose run --rm silo --migrate-status
  ```

## PostgreSQL checks (read-only)

```sh
docker compose exec postgres pg_isready -U silo
docker compose exec postgres psql -U silo -d silo -c "select version();"
docker compose exec postgres psql -U silo -d silo -c "select count(*) from pg_stat_activity;"
docker compose exec postgres psql -U silo -d silo -c "select pg_size_pretty(pg_database_size(current_database()));"
```

Only run `SELECT` statements. No `UPDATE`, `DELETE`, `DROP`, `ALTER`, or
`TRUNCATE` unless the user has a verified backup and explicitly asks for that
exact statement.

### PostgreSQL auto-tuning

With `POSTGRES_TUNE=auto` (the Compose default), Silo writes tuning values into
PostgreSQL with `ALTER SYSTEM`. Settings that need a PostgreSQL restart are
logged by name on every Silo start until PostgreSQL restarts. That warning is
harmless. Clear it during a quiet window:

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

- Log line `blob storage unavailable; readiness will retry` means the artwork
  store failed its startup probe. Check the bucket endpoint, credentials, and
  clock skew, or the local artwork directory's permissions.
- `recorded storage location no longer matches this process` or
  `private storage identity mismatch: ...` means the bucket,
  endpoint, or path was edited on an existing install. Put the old values
  back. Moving storage happens through **Admin > Settings > Infrastructure**.
- Stored credentials that stop working after a restore or migration usually
  mean the `SECRET_KEY` does not match the database. Find the original key.
  Re-entering credentials is the fallback; deleting settings rows is not.

## Container resources

```sh
docker stats --no-stream
df -h
```

Out-of-memory kills show `OOMKilled: true` in
`docker inspect --format '{{.State.OOMKilled}}' <container>`. Do not run a
bare `docker inspect`: it prints the container's environment, including
secrets.
