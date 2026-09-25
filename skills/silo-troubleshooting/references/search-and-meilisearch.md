# Search and Meilisearch

Read this when search results are missing, stale, or slow, when the admin
Search status shows a warning, or when the user runs the optional Meilisearch
engine and wants to know whether it is connected and indexed.

Upstream reference: the "Optional Meilisearch" section of the
[Docker deployment guide](https://github.com/Silo-Server/silo-server/blob/main/docs/wiki/deployment/docker.md#optional-meilisearch).

## How it fits together

- Silo's built-in search runs on PostgreSQL and needs no extra service.
  Meilisearch is an optional replacement. If the configured provider is
  `postgres`, Meilisearch plays no part; debug search as a library or
  metadata problem instead (`libraries-and-scanning.md`).
- The search settings live in the database, not in `.env`: **Admin >
  Settings > Library & Metadata > Search** (engine, URL, API key, and advanced
  options). Every one of them takes effect only after a Silo restart.
- The Compose file from the Silo repository defines a `meilisearch` service
  under the `search` profile. It needs `MEILI_MASTER_KEY` in `.env`, stores its
  data in `${SILO_DATA_ROOT:-/opt/silo}/meilisearch`, and by default publishes
  port 7700 on `127.0.0.1` only. From inside the Silo container its address is
  `http://meilisearch:7700`.
- Unraid templates and plain Docker installs do not include Meilisearch. The
  user runs it as a separate container, and the URL set in Silo must be
  reachable from inside the Silo container.
- A hidden background task, `sync_catalog_search_index` ("Sync Catalog Search
  Index"), runs at startup and every minute. It builds the index when it is
  missing or out of date, then applies catalog changes from a queue of change
  events. A second task, `rebuild_catalog_search_index`, only runs when an
  admin starts it. Neither appears in the **Admin > Scheduled Tasks** list;
  open them from the links at the bottom of the Search status panel, or at
  `/admin/tasks/sync_catalog_search_index` and
  `/admin/tasks/rebuild_catalog_search_index` in the web app.
- Silo falls back to PostgreSQL whenever Meilisearch fails, times out
  (default 800 ms), or has no usable index. **Search working does not prove
  Meilisearch is working.** Check which engine is actually answering.

## Read the search status first

In the web app: **Admin > Settings > Library & Metadata**, open **Search
status** at the bottom of the Search section. Or, with an admin API key (see
`SKILL.md`):

```sh
curl -fsS -H "Authorization: Bearer $(cat ~/.silo-key)" http://localhost:8090/api/v2/admin/catalog/search/status
```

| Field | What it tells you |
|---|---|
| `configured_provider` | What the settings ask for: `postgres` or `meilisearch`. |
| `active_provider` | What is answering searches right now. `postgres` while `configured_provider` is `meilisearch` means Silo has fallen back. |
| `degraded`, `degraded_reason` | Why it fell back, in plain words. Start here. |
| `meilisearch.configured` | `false` while `configured_provider` is `meilisearch` means the URL is empty or invalid, or Silo has not been restarted since it was set. |
| `meilisearch.healthy`, `circuit_state`, `circuit_reason`, `circuit_until` | After a failed request, Silo stops calling Meilisearch for 30 seconds (`circuit_state: open`) and records the error in `circuit_reason`. `healthy: true` only means no request has failed recently; it is not an active connection test. |
| `meilisearch.last_fallback` | The most recent error that sent a search to PostgreSQL. Survives after the 30 seconds are over. |
| `index.active_index_uid` | Empty: the index has never been built. |
| `index.rebuild_required` | The index does not match the current settings or Silo version. The background task rebuilds it. |
| `index.document_count` | Items in the index. Near zero on a large library means the build has not finished or is failing. |
| `index.pending_events` | Catalog changes waiting to be applied. It should drain within a few minutes; a number that keeps growing means sync is failing. |
| `index.dead_lettered_events` | Changes dropped after 10 failed attempts. Those items stay stale until the next rebuild. |
| `index.last_rebuild_at`, `index.last_sync_at` | When the build and the last sync finished. |
| `semantic.*` | Meaning-based search. Only relevant if the user turned it on. |

## Check the connection

Work through these in order and stop at the first one that fails. The
examples use Compose; for plain Docker or Unraid, use `docker exec
<container>` with the Meilisearch and Silo container names.

1. **Is Meilisearch running?**

   ```sh
   docker compose --profile search ps -a meilisearch
   docker compose --profile search logs --since 30m meilisearch 2>&1 | grep -E 'WARN|ERROR' | tail -n 20
   ```

   Nothing listed means the `search` profile was never started. Profiles are
   easy to lose: a later `docker compose up -d` or `pull` without
   `--profile search` skips the service. `MEILI_MASTER_KEY is required when
   enabling the search profile` in its logs means `.env` has no key; check
   with `grep -c '^MEILI_MASTER_KEY=.' .env`, never by printing it.

2. **Does Meilisearch answer on its own?** Its `/health` endpoint needs no
   key:

   ```sh
   docker compose --profile search exec -T meilisearch curl -sS -m 5 http://127.0.0.1:7700/health
   ```

   Expect `{"status":"available"}`.

3. **Can Silo reach the URL it is configured with?** Ask the user to read
   the **Meilisearch URL** from the Search settings (it is not a secret),
   then call it from inside the Silo container:

   ```sh
   docker compose exec -T silo curl -sS -m 5 http://meilisearch:7700/health
   ```

   `localhost` or `127.0.0.1` in that URL is the most common mistake: inside
   the Silo container it points at Silo itself. The settings field shows
   `http://localhost:7700` as a placeholder, which only works when Silo is not
   in a container. For Compose use `http://meilisearch:7700`; for separate
   containers use the Meilisearch container's name on a shared Docker network,
   or the host's LAN address and published port.

4. **Is the API key right?** The **Test connection** button in the settings
   only calls `/health`, which Meilisearch answers without a key. **A wrong
   key passes the test** and fails later, when the index task runs or a
   search is made. A rejected key shows up as `meilisearch HTTP 401` or
   `meilisearch HTTP 403` in `circuit_reason`, `last_fallback`, or the task
   history below. The key must be the Meilisearch master key
   (`MEILI_MASTER_KEY`) or a Meilisearch API key whose index pattern covers
   the index prefix (`silo_media_items*` by default) and allows creating,
   reading, and deleting indexes, reading and updating settings, adding and
   deleting documents, search, stats, and reading tasks. When unsure, the
   master key is simplest.

5. **Has Silo been restarted since the settings were saved?** Check for the
   restart banner, or `/api/v2/admin/server/status`. Until the restart, Silo
   keeps using the old settings, and the index task reports `Restart Silo
   before rebuilding the catalog search index`.

## Check the index build

1. **Read the task history.** In the web app, open
   `/admin/tasks/sync_catalog_search_index` (or the **Automatic maintenance**
   link in the Search status panel). With the API:

   ```sh
   curl -fsS -H "Authorization: Bearer $(cat ~/.silo-key)" 'http://localhost:8090/api/v2/admin/tasks/sync_catalog_search_index/history?limit=5'
   curl -fsS -H "Authorization: Bearer $(cat ~/.silo-key)" 'http://localhost:8090/api/v2/admin/tasks/rebuild_catalog_search_index/history?limit=5'
   ```

   Each run has a `status` and, when it failed, an `error_message`. A run that
   finds nothing to do is not recorded at all, so an empty history on a
   healthy install is normal. While a build runs, the task page shows progress
   as `Submitted N of M catalog items`; a large library can take a long time.

2. **Look for skipped runs in the logs.** Before each scheduled run, Silo
   checks that the active index still exists in Meilisearch. If that check
   fails, the run is skipped with a warning and no history entry:

   ```sh
   docker compose logs --since 30m silo 2>&1 | grep -E 'sync_catalog_search_index|catalog search'
   ```

   `scheduled task preflight failed; skipping run` with
   `task=sync_catalog_search_index`, repeating every minute, means Silo cannot
   reach Meilisearch or its key is rejected; go back to "Check the
   connection". The `error` field says which.

3. **Why are changes failing?** Read-only summary of the change queue's
   errors, run in the database shell (no user data, just error text and
   counts). `dropped` counts events that gave up after 10 attempts:

   ```sql
   select left(last_error, 160) as error, count(*) as events,
          count(*) filter (where processed_at is not null) as dropped
   from catalog_search_index_events
   where last_error <> ''
   group by 1 order by 2 desc limit 10;
   ```

4. **What does Meilisearch say?** Its failed tasks carry the underlying
   error (disk full, payload rejected, and so on). This runs inside the
   Meilisearch container, so its own shell expands the key and it is never
   printed:

   ```sh
   docker compose --profile search exec -T meilisearch sh -c 'curl -sS -m 10 -H "Authorization: Bearer $MEILI_MASTER_KEY" "http://127.0.0.1:7700/tasks?statuses=failed&limit=5"'
   docker compose --profile search exec -T meilisearch sh -c 'curl -sS -m 10 -H "Authorization: Bearer $MEILI_MASTER_KEY" http://127.0.0.1:7700/stats'
   ```

   `/stats` lists every index with its document count and whether it is
   still indexing, plus the total `databaseSize`. Silo's indexes are named
   after the prefix (`silo_media_items` or `silo_media_items_rebuild_<time>`).
   Several `_rebuild_` indexes mean earlier builds failed part way; a
   successful build removes them.

5. **Is there room?** A rebuild creates the new index next to the old one and
   deletes the old one only after the swap, so it briefly needs space for two
   copies. Check the disk holding `${SILO_DATA_ROOT:-/opt/silo}/meilisearch`
   with `df -h`.

## Messages and what they mean

| Where | Message | Meaning | Safe next step |
|---|---|---|---|
| Search status | `Meilisearch index has not been built; using Postgres search` | No build has finished yet. | Wait a minute for the task, then check its history. |
| Search status | `Search index rebuild required; using Meilisearch keyword search` | Settings or an upgrade changed the index format. The old index still serves keyword search while a new one is built. | Nothing, unless the task history shows failures. |
| Search status | `Meilisearch index schema mismatch; using Postgres search` | The old index cannot serve the current settings. | Same as above; searches use PostgreSQL until the build finishes. |
| Search status | `A newer server version owns the Meilisearch index; using Postgres search on this node` | Silo was rolled back after a newer version built the index. This version will not touch it. | Search keeps working on PostgreSQL. Upgrading again restores Meilisearch. Do not delete indexes to force a rebuild. |
| Search status | `Meilisearch is unavailable; using Postgres search: <error>` | Recent requests failed. The error explains why. | Follow "Check the connection". |
| Search status | `Meilisearch index state is unavailable; using Postgres search` | Silo could not read its index state from PostgreSQL. | A database problem; see `startup-and-database.md`. |
| Error text | `dial tcp ...: connect: connection refused`, `no such host` | Wrong URL, or Meilisearch is not running. | Steps 1 and 3 of "Check the connection". |
| Error text | `context deadline exceeded`, `Client.Timeout exceeded` | Meilisearch answered too slowly (searches allow 800 ms by default). Common while a large build is running on a small machine. | Check Meilisearch CPU and memory with `docker stats --no-stream`. Raising **Query timeout** is a settings change and needs a restart. |
| Error text | `meilisearch HTTP 401` / `meilisearch HTTP 403` | The API key is missing, wrong, or lacks a permission. | Step 4 of "Check the connection". |
| Error text | `meilisearch task N failed: <reason>` | Meilisearch rejected an indexing step. | Read the reason; check disk space and Meilisearch's failed tasks. |
| Task result | `Restart Silo before rebuilding the catalog search index` | Settings were saved but Silo has not restarted. | Restart Silo (a change; ask first). |
| Task result | `Another catalog search index maintenance task is already running` | A build or sync is already running, possibly on another node. | Wait. |
| Task result | `Catalog search rebuild failed after N documents` | The build stopped part way. | Read `error_message` in the same history entry. |
| Silo logs | `catalog search: meilisearch selected without URL; using postgres` | Meilisearch was selected with an empty URL. | Set the URL, save, restart. |
| Silo logs | `catalog search: failed to initialize meilisearch provider; using postgres` | The URL is malformed, for example missing `http://`. | Fix the URL, save, restart. |
| Silo logs | `catalog search: failed to remove superseded meilisearch indexes` | The new index is live, but an old copy could not be deleted. It only costs disk. | The next rebuild retries. |
| Meilisearch logs | `Your database version (...) is incompatible with your current engine version (...)` | The Meilisearch image was upgraded (the default tag is `latest`) and cannot open data written by the old version. | See "Fixes" below. |

## Fixes

Each of these is a change: the backup gate and one-change-at-a-time rules in
`SKILL.md` apply. Search settings changes all need a Silo restart.

- **Start Meilisearch**: `docker compose --profile search up -d meilisearch`.
  To stop later commands from dropping it, the user can add
  `COMPOSE_PROFILES=search` to `.env`.
- **Wrong URL or key**: the user corrects it in the Search settings, uses
  **Test connection** (which checks only the URL), saves, and restarts Silo.
  Then confirm with the task history and `active_provider`.
- **Rebuild the index**: the **Rebuild index** button in the Search status
  panel, or run it from `/admin/tasks/rebuild_catalog_search_index`. Searches
  keep working during the build. It loads Meilisearch and PostgreSQL, so
  suggest a quiet time. Use it after dropped events, or when the index looks
  wrong but the status is otherwise clean.
- **Meilisearch will not start after an image update**: the index holds
  nothing that is not also in PostgreSQL, so no library data is at risk.
  Either pin the previous version (`MEILISEARCH_IMAGE=getmeili/meilisearch:vX.Y`
  in `.env`, using the version from the error) and recreate the service, or
  have the user move `${SILO_DATA_ROOT:-/opt/silo}/meilisearch` aside
  themselves (safety rule 4) and start Meilisearch empty; Silo rebuilds the
  index within a minute. Meilisearch's own upgrade options are in its
  [update guide](https://www.meilisearch.com/docs/learn/update_and_migration/updating).
  Suggest pinning a specific version afterwards so updates happen on
  purpose.
- **Give up on Meilisearch for now**: setting **Search engine** back to
  **Built-in (Postgres)** and restarting is a valid, reversible choice. Say
  plainly that this turns Meilisearch off rather than fixing it.

## Do not

- Do not print `MEILI_MASTER_KEY` or the API key stored in Silo, and do not
  ask the user to paste either into the chat.
- Do not publish Meilisearch's port beyond `127.0.0.1`, or route it through a
  reverse proxy. Only Silo needs to reach it.
- Do not delete Meilisearch indexes by hand, and do not edit the
  `catalog_search_index_state` or `catalog_search_index_events` tables. Use
  the rebuild task.
