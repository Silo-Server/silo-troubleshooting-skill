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
docker compose exec silo ffprobe -v error -show_entries \
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
4. Restart Silo, then press the node's re-probe button ("Re-probe hardware")
   on **Admin > Nodes**, or call `POST /api/v2/admin/nodes/{id}/reprobe`. A reprobe is refused while
   that node is transcoding.

Inside an LXC container (Proxmox), `/dev/dri` must also be passed into the
LXC, and the device permissions must allow access from inside it.

### NVIDIA (NVENC)

1. Install the NVIDIA driver and the NVIDIA Container Toolkit on the host.
2. Use `COMPOSE_FILE=docker-compose.yml:docker-compose.nvidia.yml` and set
   `NVIDIA_GPU_COUNT`.
3. Check: `docker compose exec silo nvidia-smi`. If that fails, the problem is
   the host's driver or toolkit, not Silo.

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
- **Stale** on **Admin > Nodes** means no capability report for over 10
  minutes. **Drift** means the node's hardware got worse since it was last
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
