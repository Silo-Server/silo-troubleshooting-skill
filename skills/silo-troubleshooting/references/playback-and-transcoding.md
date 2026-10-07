# Playback, transcoding, hardware acceleration, and nodes

Use this when a title will not play, buffers, plays without sound or subtitles,
stops partway through, or when the CPU is pegged during playback.

## Pin down the failure first

Ask the user for:

1. Which title and which client (web browser, Silo iOS/tvOS/Android app, or a
   Jellyfin-compatible app, and which one).
2. On the LAN or remote.
3. Whether other titles play on the same client. One title failing points at
   the file; everything failing points at the server or network.
4. The time it happened, so the logs can be filtered.

## How Silo decides how to play a file

For each playback, Silo picks one method:

- **Direct play**: the client plays the original file as-is. Cheapest.
- **Remux / direct stream**: the container changes (for example MKV to HLS)
  and the video is copied. Audio may be converted. Light CPU.
- **Transcode**: video is re-encoded by FFmpeg. Heavy; uses the GPU if
  hardware acceleration works, otherwise the CPU.

Silo transcodes when the client cannot decode the codec, the resolution is
above what the client or its settings allow, or bandwidth limits require it.
**Admin > Activity** shows the method for each active stream, including which
node ran and served it. **Admin > Playback History** keeps it for past
sessions.

## Where to look

- **Admin > Logs**: filter by level `warn`/`error`, component `playback`,
  `transcodenode`, or `nodepool`, or search for the title name. Every log line
  from one playback shares a `playback_session_id`, so filter on that once you
  have it.
- Container logs around the time of failure:

  ```sh
  docker compose logs --since 15m silo 2>&1 | grep -iE 'playback|transcode|ffmpeg|stream'
  ```

- **Admin > Nodes**: acceleration status, node health, and scratch disk for
  every node, including the main server.

## Problem file

Probe it from inside the container:

```sh
docker compose exec silo /usr/lib/jellyfin-ffmpeg/ffprobe -v error -show_entries \
  stream=index,codec_type,codec_name,profile,width,height,pix_fmt,channels:format=duration,bit_rate \
  -of compact "/mnt/media/Movies/Film (2020)/Film (2020).mkv"
```

Things that commonly force a transcode or fail: HEVC or AV1 on clients that
lack a decoder, 10-bit HDR or Dolby Vision on SDR clients (needs tone
mapping), DTS/TrueHD audio, image-based subtitles (PGS, VobSub) that must be
burned in, and damaged files (errors from `ffprobe` itself).

## Hardware acceleration

Settings: **Admin > Settings > Playback > Hardware acceleration**. Options are
Auto, Intel Quick Sync (QSV), VA-API, NVIDIA NVENC, VideoToolbox (macOS), and
Software. Changing it needs a restart.

Silo checks each backend by running a real one-frame test encode. Results are
on **Admin > Nodes** under Acceleration:

- Green: the test encode passed.
- Amber: configured, but the test failed. Silo still tries it because an
  explicit choice is honoured, so transcodes may fail.
- `SW`: no hardware backend works; transcoding uses the CPU.

Failure reasons shown there or in the logs include
`qsv and vaapi hwaccels unavailable`, `hevc_qsv encoder unavailable`, and
`hevc_nvenc encoder unavailable`.

### Intel or AMD (VA-API / QSV)

1. The host must have `/dev/dri`: `ls -l /dev/dri` on the host.
2. The container must get it. With Compose, add the overlay:
   `COMPOSE_FILE=docker-compose.yml:docker-compose.vaapi.yml` in `.env`, then
   `docker compose up -d`. On Unraid, add `--device=/dev/dri:/dev/dri` to
   **Extra Parameters** (not an empty Device entry).
3. Check inside the container: `docker compose exec silo ls -l /dev/dri`.
4. Restart Silo, then use the node's re-probe icon button on **Admin > Nodes**
   (its tooltip reads "Re-verify this node's hardware against live devices"),
   or call `POST /api/v2/admin/nodes/{id}/reprobe`. A re-probe is refused
   while that node is transcoding.

Inside an LXC container (Proxmox), `/dev/dri` must also be passed into the
LXC, and the device permissions must allow access from inside it.

### NVIDIA (NVENC)

Docker Compose:

1. Install the NVIDIA driver and the NVIDIA Container Toolkit on the host.
2. Use `COMPOSE_FILE=docker-compose.yml:docker-compose.nvidia.yml` and set
   `NVIDIA_GPU_COUNT`.
3. Check: `docker compose exec silo nvidia-smi`. If that fails, the problem is
   the host's driver or toolkit, not Silo.
4. If `nvidia-smi` works but NVENC still fails, the container may lack the
   driver's video capability. Add `NVIDIA_DRIVER_CAPABILITIES:
   compute,video,utility` to the `silo` service's environment in an override
   file, then recreate the container.

Unraid:

1. Install the **Nvidia-Driver** plugin and reboot if prompted.
2. Edit the Silo container with **Advanced View** on, add `--runtime=nvidia`
   to **Extra Parameters**, and enter the GPU UUID (or `all`) in **NVIDIA GPU
   UUID**. Leave `NVIDIA_DRIVER_CAPABILITIES` at `compute,video,utility`.

The NVIDIA driver caps concurrent encode sessions on consumer cards. Past that
cap, new transcodes fail even though the card has headroom.

## HDR looks washed out or grey

That is HDR shown on an SDR screen without tone mapping. **Admin > Settings >
Playback** has **Enable Hardware HDR Tone Mapping** and **Enable Software HDR
Tone Mapping**. Software tone mapping is CPU-heavy. The better fix is a client
that supports HDR direct play.

## 4K will not play on some clients

If **Allow 4K transcoding** is off and the client cannot direct play the 4K
file, playback ends with "A lower-resolution source is required because 4K
transcoding is disabled." Turn the setting on (and check the GPU can handle
it), or add a 1080p version of the title.

## Chapter previews missing

Chapter menus work without thumbnails; this is only about the preview images
on the seek bar and chapter list. They are stored in artwork storage, which is
local disk on a default install. S3 is not required.

1. **Is it switched on?** Under **Admin > Libraries**, edit the library and
   check **Generate chapter thumbnails** in its advanced settings. If the
   switch is greyed out, Silo has no artwork storage; check the storage
   settings under **Admin > Settings > Storage & Database**.
2. **Does the file have chapters?** Without chapter markers there is nothing to
   generate:

   ```sh
   docker compose exec silo /usr/lib/jellyfin-ffmpeg/ffprobe -v error -show_chapters \
     -of compact "/mnt/media/Movies/Film (2020)/Film (2020).mkv"
   ```

3. **Read the reason.** In **Admin > Logs**, filter by component
   `chapterthumbs` and open a line to see its attributes. The default log
   capture level (`info`) already includes every line below.

| Log message and `reason` | Meaning and next step |
|---|---|
| `request skipped`, `folder_disabled` | The library switch is off, or the folder is disabled. |
| `request skipped`, `no_chapters` | The file has no chapter markers. Nothing to fix in Silo. |
| `request skipped`, `no_eligible_chapters` | Every chapter already has an image or is waiting to be retried. |
| `request skipped`, `hdr_policy_disabled` | **Admin > Settings > Playback**, **HDR handling** is set to skip HDR and Dolby Vision, and this file needs tone mapping. |
| `extract failed`, `tonemap_unsupported` | HDR source that could not be tone mapped. **Software HDR tone mapping** in the same group works without a GPU but is slow. |
| `probe failed`, `probe_failed` | Silo could not read the chapter metadata. Treat it as a problem file (above). |
| `extract failed`, `ffmpeg_probe_failed` | FFmpeg could not set up frame extraction. Treat it as a problem file. |
| `extract failed`, `decode_invalid_data` | FFmpeg found invalid data in the file. Usually a damaged file; check it with `ffprobe`. |
| `request skipped`, `file_cooldown` | The whole file is waiting after an earlier failure; `retry_after` says until when. |
| `upload failed` | Extraction worked but the image could not be saved. Check free space and permissions of local artwork storage, or the bucket credentials and endpoint if artwork is in S3. |

**When it runs.** Opening a title's page queues its previews, playback queues
them at a higher priority, and a hidden Chapter Thumbnail Backfill task looks
for missing ones every six hours. That task does not appear under **Admin >
Scheduled Tasks**, and there is no button to run it. If **Generate chapter
thumbnails on** (**Admin > Settings > Playback**) sends the work to a
transcode node, that node must be connected and healthy.

**Retry timing.** A failed chapter is retried 15 minutes after its first
failure, 1 hour after its second, 6 hours after its third, and 24 hours after
each failure from then on.
`decode_invalid_data`, `ffmpeg_probe_failed`, and `tonemap_unsupported` pause
the whole file instead: Silo logs `chapter thumbnail file marked failed` with
a `retry_after` time, and until then every request for the file logs
`file_cooldown`. `decode_invalid_data` starts at 24 hours on its first
failure, so reopening the title a few minutes later will not retry it. A file
waiting out its cooldown is not stuck; tell the user when it will be retried
rather than changing anything.

To see how many files are paused, and why, without reading any rows:

```sh
docker compose exec -T postgres psql -U silo -d silo -At <<'SQL'
select split_part(chapter_thumbnail_last_error, ':', 1) as reason,
       count(*) as files,
       count(*) filter (where chapter_thumbnail_retry_after > now()) as still_waiting
from media_files
where coalesce(chapter_thumbnail_last_error, '') <> ''
group by 1 order by 2 desc;
SQL
```

This counts files whose latest attempt ended in a whole-file failure; a later
successful run clears it. Do not write to these columns to force a retry.

## Transcode nodes (distributed setups)

Only relevant when the user runs separate `proxy` or `transcode` containers.

- Every role needs the same `SECRET_KEY`, the same PostgreSQL and Redis, and
  the **same absolute media paths** as the main server.
- Set `NODE_URL` on each node explicitly. Without it the node guesses
  `http://localhost:<port>` and can pick up another node's settings.
- Node names must be unique. After renaming a node in the admin UI, update
  that node's `NODE_NAME` to match.
- Health checks run every 30 seconds. `stream node unhealthy` in the logs names
  the node. Existing streams move to a healthy node at their next segment.
- **Stale** in a node's Acceleration block means no health check has
  confirmed that hardware inventory for about 10 minutes. **Drift** means the node's hardware got worse since it was last
  seen (for example it lost its GPU).
- Scratch disk: nodes at 95% or more of their transcode volume stop receiving
  new transcodes. `transcode scratch guard ignored: every eligible node is over
  the scratch threshold` means every node is full. Free space in the transcode
  directory or enlarge the volume.

## Do not

- Do not run containers `--privileged` to "fix" GPU access. Pass the specific
  device instead.
- Do not delete files in the transcode directory while streams are playing.
- Do not turn off transcoding server-wide to fix one client.
