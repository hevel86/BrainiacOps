# Jellyfin transcoding configuration

Updated 2026-10-06. Production runs the official `jellyfin/jellyfin:12.2` image, pinned by digest in [deploy.yaml](deploy.yaml); see [MIGRATION.md](MIGRATION.md) for upgrade status. Previous LinuxServer playback results do not validate the official image.

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

The Meilisearch pod shares the `app: jellyfin` label, so `deployment/jellyfin` exec/log shortcuts can select the wrong pod. Select the server pod explicitly:

```bash
jf_pod=$(kubectl get pods -n default -l app=jellyfin,component=server -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default "$jf_pod" -c jellyfin -- id
kubectl exec -n default "$jf_pod" -c jellyfin -- stat -c '%u:%g %a %n' /config /config/data /dev/dri/renderD128
kubectl exec -n default "$jf_pod" -c jellyfin -- curl -fsS --max-time 10 http://localhost:8096/health
kubectl exec -n default "$jf_pod" -c jellyfin -- /usr/lib/jellyfin-ffmpeg/ffmpeg -version
kubectl exec -n default "$jf_pod" -c jellyfin -- /usr/lib/jellyfin-ffmpeg/vainfo --display drm --device /dev/dri/renderD128
kubectl exec -n default "$jf_pod" -c jellyfin -- df -h /transcode
```

Synthetic smoke tests (QSV encode, then OpenCL initialization; VAAPI must be initialized first):

```bash
kubectl exec -n default "$jf_pod" -c jellyfin -- /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -loglevel error \
  -init_hw_device vaapi=va:/dev/dri/renderD128 -init_hw_device qsv=qs@va -filter_hw_device qs \
  -f lavfi -i testsrc2=size=1280x720:rate=30 -vf 'format=nv12,hwupload=extra_hw_frames=64' \
  -c:v h264_qsv -frames:v 60 -f null -
kubectl exec -n default "$jf_pod" -c jellyfin -- /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -loglevel error \
  -init_hw_device vaapi=va:/dev/dri/renderD128 -init_hw_device opencl=ocl@va \
  -f lavfi -i color=size=64x64 -frames:v 1 -f null -
```

Driver enumeration alone is insufficient. Play a known direct-play title, force an SDR transcode, and force HDR-to-SDR playback on an SDR client. Check playback completion/seeking, correct colors, and FFmpeg logs for hardware decoding/encoding and tone mapping without software fallback or permission errors. Check memory and restart counts during the test. Keep logs containing media paths under `/tmp`, outside Git.

Stage-1 results on official 10.11.11: identity, paths and render-device access correct; `vainfo` (iHD), the synthetic QSV encode and OpenCL initialization passed; desktop playback via Fladder was reported good (direct-play vs transcode not classified). On 12.2: identity and paths correct; `vainfo`, the synthetic QSV encode and OpenCL initialization passed. Real direct-play, SDR transcode and HDR-to-SDR playback on 12.2 are still pending. Use the acceptance checklist in [MIGRATION.md](MIGRATION.md).
