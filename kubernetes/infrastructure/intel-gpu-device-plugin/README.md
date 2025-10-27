# Intel GPU Device Plugin

This deployment uses `intel/intel-gpu-plugin:0.34.0` to expose Intel GPUs to the cluster.

## GPU sharing

The DaemonSet is configured with `-shared-dev-num=4` and `-allocation-policy=balanced`. This slices each physical Intel GPU into four allocatable shares so that several pods can run on the same card. Each pod should continue requesting `gpu.intel.com/i915: 1`. Kubernetes now sees four allocatable units per GPU and will schedule up to four pods per node (per GPU) before reporting the resource as fully allocated.

If you need a different level of over-subscription, edit `kubernetes/infrastructure/intel-gpu-device-plugin/manifests/intel-gpu-plugin.yaml` and change the value passed to `-shared-dev-num`. For example, setting `-shared-dev-num=8` would allow eight pods to bind to the same GPU. Leave the allocation policy at `balanced` unless you prefer `packed` semantics (fill one GPU to capacity before using the next).

After modifying the manifest, apply the updated Kustomization to roll the DaemonSet:

```bash
kubectl apply -k kubernetes/infrastructure/intel-gpu-device-plugin
```
