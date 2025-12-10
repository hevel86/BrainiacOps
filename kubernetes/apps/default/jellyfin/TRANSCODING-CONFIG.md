# Jellyfin Transcoding Configuration Notes

**Last Updated**: 2025-12-10
**Pod Image**: `lscr.io/linuxserver/jellyfin:10.11.4`
**Role**: Backup media server (Primary: Plex)

## Current Configuration Summary

Jellyfin is configured to use Intel Quick Sync Video hardware acceleration through VAAPI on Intel GPUs. The configuration has been optimized to work with the stock container image (no custom packages installed).

**Use Case**: Jellyfin serves as a backup to Plex. All client TVs support HDR/Dolby Vision, so HDR→SDR tone mapping is not required.

### Hardware Acceleration Settings

**Location**: `/config/encoding.xml` (inside the pod)

```xml
<HardwareAccelerationType>vaapi</HardwareAccelerationType>
<VaapiDevice>/dev/dri/renderD128</VaapiDevice>
<EnableTonemapping>false</EnableTonemapping>
<EnableVppTonemapping>false</EnableVppTonemapping>
<EnableHardwareEncoding>true</EnableHardwareEncoding>
<EnableIntelLowPowerH264HwEncoder>true</EnableIntelLowPowerH264HwEncoder>
<EnableIntelLowPowerHevcHwEncoder>true</EnableIntelLowPowerHevcHwEncoder>
```

### Key Configuration Decisions

1. **VAAPI vs QSV**: Using `vaapi` instead of `qsv` for hardware acceleration
   - Both access Intel Quick Sync Video hardware
   - VAAPI is the Linux API that accesses QSV
   - Functionally equivalent performance

2. **Tone Mapping: DISABLED**
   - `EnableTonemapping`: false
   - `EnableVppTonemapping`: false
   - **Reason**: Jellyfin's tone mapping implementation requires OpenCL runtime
   - **Impact**: HDR content will not be tone-mapped to SDR
   - **Trade-off**: Accepted to keep container stock (no custom packages)

3. **Trickplay Configuration**
   - Hardware acceleration: Enabled
   - Hardware encoding: Enabled (using `mjpeg_vaapi`)
   - Works perfectly with current settings

## Problem History

### Issue Encountered
Jellyfin was attempting to use OpenCL for HDR tone mapping, causing errors:
```
[AVHWDeviceContext @ 0x...] Failed to get number of OpenCL platforms: -1001.
Device creation failed: -19.
Failed to set value 'opencl=ocl@va' for option 'init_hw_device': No such device
```

### Root Cause
When tone mapping is enabled (either `EnableTonemapping` or `EnableVppTonemapping`), Jellyfin generates ffmpeg commands that include:
```bash
-init_hw_device opencl=ocl@va
hwmap=derive_device=opencl:mode=read,tonemap_opencl=...
```

The stock linuxserver/jellyfin container does not include OpenCL runtime libraries:
- Missing: `ocl-icd-libopencl1`
- Missing: `intel-opencl-icd`

### Solution Implemented
Disabled all tone mapping to eliminate OpenCL dependency while maintaining hardware acceleration for transcoding and trickplay generation.

## Current Status

### ✅ Working Features
- Hardware-accelerated video decoding (H.264, HEVC, VC1, AV1)
- Hardware-accelerated video encoding (H.264, HEVC)
- Hardware-accelerated transcoding
- Trickplay thumbnail generation (hardware-accelerated)
- Intel Quick Sync Video utilization via VAAPI

### ⚠️ Known Limitations
- **No HDR → SDR tone mapping**
  - HDR content will display without tone mapping
  - May appear washed out on SDR displays
  - Will display correctly on HDR-capable displays
  - **Not an issue for this environment**: All TVs support HDR/Dolby Vision

### 🔧 How to Enable Tone Mapping (Future)

If HDR tone mapping becomes required, there are three options:

**Option 1: Add OpenCL to Container (Recommended if needed)**

Create a custom Dockerfile:
```dockerfile
FROM lscr.io/linuxserver/jellyfin:10.11.4

RUN apt-get update && \
    apt-get install -y \
    ocl-icd-libopencl1 \
    intel-opencl-icd && \
    rm -rf /var/lib/apt/lists/*
```

Then update [deploy.yaml](deploy.yaml):
```yaml
image: your-registry/jellyfin-opencl:10.11.4
```

And modify [encoding.xml](encoding.xml) inside the pod:
```xml
<EnableTonemapping>true</EnableTonemapping>
<EnableVppTonemapping>false</EnableVppTonemapping>
```

**Option 2: Wait for Jellyfin Update**

Future Jellyfin versions may support pure VAAPI tone mapping without OpenCL dependency.

**Option 3: Software Tone Mapping**

Not recommended - extremely slow, no hardware acceleration.

## Verification Commands

### Check Current Encoding Settings
```bash
kubectl exec -n default deployment/jellyfin -- cat /config/encoding.xml | grep -E "HardwareAccelerationType|EnableTonemapping|EnableVppTonemapping"
```

### Monitor Transcoding Logs
```bash
kubectl logs -n default -l app=jellyfin --tail=100 -f | grep -E "ffmpeg|transcode|trickplay" -i
```

### Check Trickplay Status
```bash
kubectl logs -n default -l app=jellyfin | grep -i trickplay
```

### Verify Hardware Acceleration is Working
Look for these in the logs during transcoding:
- `init_hw_device vaapi=va:/dev/dri/renderD128`
- `hwaccel vaapi`
- `h264_vaapi` or `hevc_vaapi` (encoding)
- `mjpeg_vaapi` (trickplay)

## Backup Information

A Longhorn snapshot was taken before making configuration changes (2025-12-10).

To restore original configuration if needed:
1. Restore from Longhorn snapshot, OR
2. Reset encoding settings via Jellyfin Web UI: Dashboard → Playback → Transcoding

## GPU Device Access

The pod has access to Intel GPU via:
```yaml
resources:
  requests:
    gpu.intel.com/i915: "1"
  limits:
    gpu.intel.com/i915: "1"
securityContext:
  privileged: true
```

Device path: `/dev/dri/renderD128`

## Related Files

- [deploy.yaml](deploy.yaml) - Deployment configuration with GPU allocation
- [pvc.yaml](pvc.yaml) - PersistentVolumeClaims including config storage
- [ingressroute.yaml](ingressroute.yaml) - Traefik ingress configuration
- [svc.yaml](svc.yaml) - Service definition

## Additional Notes

- Config changes made via XML editing require pod restart to take effect
- Changes made in Web UI are immediately written to XML files
- Jellyfin reads `encoding.xml` on startup
- The `encoding.xml` file persists on the `jellyfin-config-lh` PVC (Longhorn storage)

## Test Results

**Date**: 2025-12-10

| Feature | Status | Notes |
|---------|--------|-------|
| Video Playback (SDR) | ✅ Working | Full hardware acceleration |
| Video Playback (HDR) | ⚠️ Limited | Plays but no tone mapping |
| Transcoding | ✅ Working | Hardware-accelerated encoding/decoding |
| Trickplay Generation | ✅ Working | No OpenCL errors, using mjpeg_vaapi |
| Intel QSV Utilization | ✅ Working | Via VAAPI interface |

---

**For questions or issues, reference this document and the original troubleshooting session from 2025-12-10.**
