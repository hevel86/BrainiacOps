# Image packaging and stable-release guard

The pinned Home Operations image packages the same stable upstream application release.
Its packaging advertises develop; the public package-info ConfigMap and explicit update-branch environment override preserve master.

Renovate is restricted to this verified application version (digest refresh PRs remain enabled and require review).
Do not relax the version rule without checking the corresponding upstream GitHub release is non-prerelease and the image actually packages that release.
For a future approved upgrade, update the image tag/digest, package_info PackageVersion, and allowedVersions rule together.
Keep Branch=master and numeric UID/GID 1000; do not change media ownership or add fsGroup.
