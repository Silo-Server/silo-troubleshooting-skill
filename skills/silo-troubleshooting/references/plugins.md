# Plugins

Use this when a plugin will not install, shows an error, or a feature that a
plugin provides (TVDB metadata, intro markers, watch sync, network access,
autoscan sources) stops working.

## How plugins run

- Each plugin is a separate process that Silo starts and talks to over gRPC.
- Most plugins start on first use. The first metadata lookup after a restart
  can be slower while the plugin process starts.
- Network-access plugins (overlay networks) run all the time. Silo restarts
  them with backoff after a crash. After ten failures in a row the plugin is
  marked failed and stays down until an admin restarts it.
- Silo installs `silo.tmdb`, `silo.tvdb`, and `silo.theintrodb` at startup if
  they are missing and available in the official catalog. Auto-updates also
  run at startup.
- Installed plugins are cached under `/var/lib/silo/plugins` in the container
  (`SILO_PLUGIN_CACHE_DIR`; `/opt/silo/plugins` on the host with Compose).

## Where to look

- **Admin > Plugins**: install state, enabled switch, configuration, and
  restart.
- Logs:

  ```sh
  docker compose logs --since 1h silo 2>&1 | grep -iE 'plugin'
  ```

| Message | Meaning |
|---|---|
| `plugin instance retired` | The plugin process exited or failed its health check. The `error` field says which. |
| `preload enabled plugins: ...` (fatal at startup) | An enabled plugin could not be loaded, so Silo stopped. |
| `plugin auto-update failed`, `failed to run plugin auto-update`, or `plugin auto-update operation failed` | The startup update check failed. Silo keeps running on the installed version. |
| `binary checksum mismatch: expected ..., got ...` | The downloaded plugin does not match its manifest. A corrupted download or a bad catalog entry. |
| `plugin manifest checksum is required` / `plugin manifest supported_platforms is required` | The plugin package is malformed. Report it to the plugin's author. |

## Safe fixes, in order

1. Restart the plugin from **Admin > Plugins** (or
   `POST /api/v2/admin/plugins/installations/{id}/restart`).
2. Check the plugin's settings. API keys for third-party services (TVDB,
   Trakt, MDBList, and so on) are the usual cause.
3. Disable the plugin, restart Silo, and confirm the rest of the server works.
4. Reinstall the plugin from the catalog.

If Silo will not start because of a plugin (`preload enabled plugins: ...`),
read the wrapped error first. Silo keeps each plugin's files in the plugin
cache and rebuilds them from the database when they are missing or damaged,
so the usual causes are on the host:

- The disk holding the plugin cache is full (`df -h`).
- The cache directory is not writable, or mounted read-only
  (`/opt/silo/plugins` with Compose, `/mnt/user/appdata/silo/plugins` on
  Unraid).

With Silo stopped, moving the plugin cache directory aside (renaming it, not
deleting it) is reversible, and Silo rebuilds it at the next start. Moving
data directories is a step the user runs in their own terminal; show them the
commands. If the error persists, report it with
the log lines (see `bug-reports-and-feature-requests.md`). Do not delete rows from the plugin
tables.

## Do not

- Do not delete the plugin cache directory while Silo is running.
- Do not install plugin binaries from sources the user does not trust.
  Plugins run as processes inside the Silo container, with the same access to
  files and the network as Silo itself.
