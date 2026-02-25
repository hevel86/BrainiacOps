# Jellyfin Transcoding Configuration Notes

**Last Updated**: 2026-02-25
**Pod Image**: `lscr.io/linuxserver/jellyfin:10.11.6`
**Role**: Backup media server (Primary: Plex)
**Hardware**: MINISFORUM MS-01 with Intel i5-12600H (12th Gen Alder Lake, Iris Xe Graphics)

## Current Configuration Summary

Jellyfin is configured to use Intel Quick Sync Video (QSV) hardware acceleration on Intel Iris Xe Graphics (12th gen). The configuration utilizes the `linuxserver/mods:jellyfin-opencl-intel` Docker mod to enable full HDR to SDR tone mapping. Transcoding is performed in a RAM-backed `emptyDir` for maximum performance and zero SSD wear.

**Use Case**: Jellyfin serves as a backup to Plex. All client TVs support HDR/Dolby Vision, but HDR→SDR tone mapping is now fully supported for mobile clients and SDR displays.

### Hardware Acceleration Settings

**Location**: `/config/encoding.xml` (inside the pod)

```xml
<HardwareAccelerationType>qsv</HardwareAccelerationType>
<QSVDevice>/dev/dri/renderD128</QSVDevice>
<EnableTonemapping>true</EnableTonemapping>
<EnableVppTonemapping>true</EnableVppTonemapping>
<EnableHardwareEncoding>true</EnableHardwareEncoding>
<EnableIntelLowPowerH264HwEncoder>true</EnableIntelLowPowerH264HwEncoder>
<EnableIntelLowPowerHevcHwEncoder>true</EnableIntelLowPowerHevcHwEncoder>

<!-- Hardware Decoding Codecs -->
<HardwareDecodingCodecs>
  <string>mpeg2video</string>
  <string>mpeg4</string>
  <string>vp8</string>
  <string>vp9</string>
  <string>h264</string>
  <string>vc1</string>
  <string>hevc</string>
  <string>av1</string>
</HardwareDecodingCodecs>

<!-- HEVC Range Extensions Support -->
<EnableDecodingColorDepth10Hevc>true</EnableDecodingColorDepth10Hevc>
<EnableDecodingColorDepth10Vp9>true</EnableDecodingColorDepth10Vp9>
<EnableDecodingColorDepth10HevcRext>true</EnableDecodingColorDepth10HevcRext>
<EnableDecodingColorDepth12HevcRext>false</EnableDecodingColorDepth12HevcRext>
```

**Note**: 12-bit HEVC RExt is disabled because Intel Iris Xe (12th gen) does not have full hardware support for 12-bit decoding. 10-bit HEVC (used by all consumer HDR content) is fully hardware accelerated.

### Key Configuration Decisions

1. **VAAPI vs QSV**: Switched to `qsv` (Intel Quick Sync Video)
   - Offers better integration with Intel-specific features compared to the generic VAAPI.
   - More efficient for high-bitrate HEVC workloads.

2. **Tone Mapping: ENABLED**
   - **Method**: Enabled via `linuxserver/mods:jellyfin-opencl-intel`.
   - **Benefit**: HDR content is now correctly tone-mapped to SDR for compatible clients, preventing "washed out" colors.

3. **RAM Transcoding**
   - **Mount**: `/transcode` is backed by a `Memory` medium `emptyDir`.
   - **Size**: 4GiB (sufficient for multiple 4K transcodes with "Throttle Transcoding" enabled).
   - **Reason**: Maximum performance (scrubbing/seeking) and zero SSD wear.

## Problem History (RESOLVED)

### Issue Encountered
Jellyfin was previously unable to use OpenCL for HDR tone mapping because the stock image lacked the required libraries, causing ffmpeg errors.

### Solution Implemented
Applied the `linuxserver/mods:jellyfin-opencl-intel` Docker mod in `deploy.yaml`. This mod installs `ocl-icd-libopencl1` and `intel-opencl-icd` at container runtime, satisfying the OpenCL dependency for tone mapping.

## Current Status

### ✅ Working Features (Intel i5-12600H Iris Xe)
- Hardware-accelerated video decoding:
  - H.264, HEVC (8/10-bit), VP8, VP9, AV1, VC1, MPEG2, MPEG4
- Hardware-accelerated video encoding:
  - H.264 & HEVC (with low-power mode)
- **Full HDR → SDR Tone Mapping**
- **Ultra-fast RAM-based transcoding**
- Trickplay thumbnail generation
- Intel Quick Sync Video via QSV interface

### ⚠️ Known Limitations
- **No 12-bit HEVC RExt support**
  - Intel Iris Xe (12th gen) lacks hardware support for 12-bit HEVC Range Extensions.
  - Not an issue for consumer content.

## Verification Commands

### Check Current Encoding Settings
```bash
kubectl exec -n default deployment/jellyfin -- cat /config/encoding.xml | grep -E "HardwareAccelerationType|EnableTonemapping|EnableVppTonemapping"
```

### Monitor Transcoding Logs
```bash
kubectl logs -n default -l app=jellyfin --tail=100 -f | grep -E "ffmpeg|transcode|trickplay" -i
```

### Verify RAM Disk Usage
```bash
kubectl exec -n default deployment/jellyfin -- df -h /transcode
```

## Intel i5-12600H Hardware Capabilities

**CPU**: 12th Gen Intel Core i5-12600H (Alder Lake-P)
**GPU**: Intel Iris Xe Graphics (96 EUs)
**Quick Sync Video Generation**: Gen 12.5

**Hardware Decode Support**:
- H.264 (AVC): All profiles, 8-bit
- HEVC (H.265): Main, Main10, Main10 RExt (8-bit, 10-bit)
- VP9: Profile 0, Profile 2 (8-bit, 10-bit)
- AV1: 8-bit, 10-bit
- MPEG2, MPEG4, VC1

## GPU Device Access

The pod has access to Intel GPU via the Intel GPU Device Plugin:
```yaml
resources:
  requests:
    gpu.intel.com/i915: "1"
  limits:
    gpu.intel.com/i915: "1"
securityContext:
  fsGroup: 1000
```

Device path: `/dev/dri/renderD128`

## Related Files

- [deploy.yaml](deploy.yaml) - Deployment configuration with OpenCL mod and RAM transcode
- [pvc.yaml](pvc.yaml) - PersistentVolumeClaims for config and media
- [ingressroute.yaml](ingressroute.yaml) - Traefik ingress configuration
- [svc.yaml](svc.yaml) - Service definition

## Test Results

**Date**: 2026-02-25

| Feature | Status | Notes |
|---------|--------|-------|
| Video Playback (SDR) | ✅ Working | Full QSV acceleration |
| Video Playback (HDR) | ✅ Working | Full Tone Mapping enabled |
| Transcoding | ✅ Working | RAM-based, low-power mode active |
| Trickplay Generation | ✅ Working | Hardware-accelerated |
| Intel QSV Utilization | ✅ Working | Native QSV interface |

---
