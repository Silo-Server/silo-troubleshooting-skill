# Libraries, scanning, and metadata

Use this when media is missing, duplicated, wrongly matched, or has no artwork
or descriptions.

## Check in this order

1. **Can the Silo container see the files?** Libraries store the path *inside
   the container* (Docker default: `MEDIA_ROOT` on the host is mounted
   read-only at `/mnt/media`). List the folder from inside the container:

   ```sh
   docker compose exec silo ls -la /mnt/media/Movies | head
   ```

   Empty output or `Permission denied` means the problem is the mount or host
   permissions, not Silo. On Unraid the template maps `/mnt/user/data` to the
   same path inside the container.

2. **Does the library point at that in-container path?** Compare the folder
   shown in **Admin > Libraries** with the path you just listed. A host path
   (`/srv/media/...`) in a library record will never resolve inside the
   container. Existing installations must keep the in-container path their
   library records already store; changing the mount target instead of the
   library record strands every existing item.

3. **Is the file named in a way Silo understands?** Silo's naming guide covers
   movie and series layouts, provider-ID tags such as `{tmdb-603}`,
   `{tvdb-81189}`, `{imdb-tt0133093}`, extras, and ignored "Sample"/"Subs"
   folders. Point the user at the Silo documentation page
   "Media folder and naming" and compare one failing path against it.

4. **Is something telling the scanner to skip it?** These files exclude a
   directory:
   - `.nomedia`: skip the directory entirely.
   - `.ignore`: gitignore-style patterns (Jellyfin-compatible).
   - `.siloignore`: glob patterns (Plex-compatible).

   Search for them above the missing file:

   ```sh
   docker compose exec silo sh -c 'd=/mnt/media/Movies/Some\ Movie; while [ "$d" != / ]; do ls -a "$d" | grep -E "^\.(nomedia|ignore|siloignore)$" && echo "  in $d"; d=$(dirname "$d"); done'
   ```

5. **Did the scan run and what did it log?** Trigger a scan from
   **Admin > Libraries**, then read **Admin > Logs** filtered to component
   `scanner`, or the container logs:

   ```sh
   docker compose logs --since 30m silo 2>&1 | grep -i 'scanner'
   ```

## Log messages and what they mean

| Message | Meaning | Safe next step |
|---|---|---|
| `scanner: library root unreachable` | The library folder is missing or unreadable inside the container. | Fix the mount or permissions, then rescan. |
| `scanner: walk could not read part of this scope; affected paths excluded from missing-file reconciliation` | Some subfolders were unreadable. Silo kept their existing items instead of deleting them. | Fix permissions on the paths listed in `unreadable_paths`. |
| `scanner: directory read failed` / `scanner: walk lstat failed` | A specific directory or file could not be read. | Check permissions and whether it is a broken symlink or a network share that dropped. |
| `scanner: ffprobe failed` | The file could not be probed. Often a corrupt or partially copied file. | Run `ffprobe` on it inside the container (see below). |
| `scanner: file processing failed` | One file failed; the rest of the scan continued. | Read the `error` field on the same line. |
| `scanner: empty roots still hold cataloged files; protecting them from cleanup` | A library folder looked empty while the catalog still has items there. Silo refused to delete them. This usually means a network mount is down. | Remount the share. Do **not** "fix" this by removing the library. |
| `scanner: left files untouched under offline roots` | Same protection as above. | Same. |

Probe a suspect file:

```sh
docker compose exec silo ffprobe -v error -show_format -show_streams "/mnt/media/Movies/Film (2020)/Film (2020).mkv" | head -40
```

## Wrong or missing metadata

- TMDB matching is built in and works without an API key; Silo ships a default
  key. TVDB comes from the `silo.tvdb` plugin. Silo installs `silo.tmdb`,
  `silo.tvdb`, and `silo.theintrodb` automatically at startup if they are
  missing and available in the official catalog.
- Check **Admin > Plugins** for the provider's state and configuration. Check
  **Admin > Settings > Providers** for provider order and keys.
- `tmdb: rate limited after N retries` or `tmdb: server error ...` in the logs
  means TMDB itself refused or failed. Wait and retry; changing Silo settings
  will not help.
- Fix a single wrong match from the item's menu in the web app: **Match Item**
  picks the right title, **Refresh Metadata** refetches it, and **Edit
  Metadata** overrides fields by hand. A folder-name tag such as `{tmdb-12345}`
  pins the match and survives rescans.

## Triggering scans

- UI: **Admin > Libraries** (scan one library or all). Autoscan sources for
  Sonarr/Radarr live on a tab of the same page.
- API (admin token): `POST /api/v2/scan` with an optional `library_id`, and
  `POST /api/v2/scan/cancel` with `library_id`. Do not blindly retry these if a
  reply is lost; check the scan status first.
- A full scan also runs daily at 02:00 server-local time.
- Scans only run on `integrated` or `api` servers, not on `proxy` or
  `transcode` nodes.

## Do not

- Do not delete a library and re-add it to "force a clean scan". Deleting a
  library removes its file records, library collections, and per-library
  provider settings, and every item has to be scanned and matched again.
- Do not edit `media_items` or `media_files` rows in PostgreSQL by hand.
- Do not remount media at a different in-container path on an existing install.
