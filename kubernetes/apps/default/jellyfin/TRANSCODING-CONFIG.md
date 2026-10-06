# Jellyfin transcoding configuration

Updated 2026-10-06. The desired stage-1 image is official `jellyfin/jellyfin:10.11.11`, pinned by digest in [deploy.yaml](deploy.yaml). Production remains on LinuxServer until the maintenance procedure in [MIGRATION.md](MIGRATION.md) is completed. Previous LinuxServer playback results do not validate the official image.

## Image and persistent paths

The server runs as UID/GID `1000:1000`, with `fsGroup: 1000`. The existing `jellyfin-config-lh` PVC and its LinuxServer directory layout are retained:

| Setting | Path |
| --- | --- |
| Data, databases and plugins | `/config/data` |
| Configuration, including `encoding.xml` | `/config` |
| Cache and font cache | `/config/cache` |
| Logs | `/config/log` |
| TV / movies | `/data/tv` / `/data/movies` |
| Transcode scratch | `/transcode` |

The official image supplies its web client at `/jellyfin/jellyfin-web`, FFmpeg at `/usr/lib/jellyfin-ffmpeg/ffmpeg`, and Intel drivers. Keep the image defaults for web and FFmpeg paths. LinuxServer's `PUID`, `PGID`, and `DOCKER_MODS` variables are removed; the old OpenCL installation mod is unnecessary with the official image. See [container documentation](https://jellyfin.org/docs/general/installation/container/).

## Hardware acceleration

The Intel GPU device plugin allocates one `gpu.intel.com/i915` device. Existing settings in `/config/encoding.xml` should retain QSV, `/dev/dri/renderD128`, hardware encoding, and the configured VPP/OpenCL tone-mapping options. Do not overwrite the file during migration. Confirm the actual encoder path and transcode temporary directory in the dashboard after startup.

`/transcode` is an 8 GiB memory-backed `emptyDir`; its usage counts toward pod memory. The server requests 1 CPU / 4 GiB and allows 4 CPUs / 16 GiB. `Recreate` avoids concurrent access to the RWO configuration volume.

The preflight on 2026-10-06 found config directories owned by `1000:1000` and the render device at mode `0666`. Recheck device permissions after rollout or rescheduling. If access changes, use the observed device GID in `supplementalGroups`; do not assume `fsGroup` changes device ownership.

## Verification after each stage

```bash
kubectl exec -n default deployment/jellyfin -- id
kubectl exec -n default deployment/jellyfin -- stat -c '%u:%g %a %n' /config /config/data /dev/dri/renderD128
kubectl exec -n default deployment/jellyfin -- /usr/lib/jellyfin-ffmpeg/ffmpeg -version
kubectl exec -n default deployment/jellyfin -- /usr/lib/jellyfin-ffmpeg/vainfo --display drm --device /dev/dri/renderD128
kubectl exec -n default deployment/jellyfin -- df -h /transcode
```

Driver enumeration alone is insufficient. Play a known direct-play title, force an SDR transcode, and force HDR-to-SDR playback on an SDR client. Check playback completion/seeking, correct colors, and FFmpeg logs for hardware decoding/encoding and tone mapping without software fallback or permission errors. Check memory and restart counts during the test. Keep logs containing media paths under `/tmp`, outside Git.

All official-image playback checks remain pending until rollout; use the acceptance checklist in [MIGRATION.md](MIGRATION.md).
