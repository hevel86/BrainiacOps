#!/bin/sh
set -eu
umask 027
base=/config/official-nextcloud
legacy=/config/www/nextcloud
html=/var/www/html

test "$(id -u)" = 1000 && test "$(id -g)" = 1000
# This marker must already exist; there is no fresh-install fallback.
test -f /data/.ncdata || test -f /data/.ocdata

if [ ! -f "$base/.prepared" ]; then
    test -s "$legacy/config/config.php"
    mkdir -p "$base/config" "$base/custom_apps" "$base/themes"
    rsync -rl "$legacy/config/" "$base/config/"
    rsync -rl "$legacy/themes/" "$base/themes/"
    # Core apps come from the new release. Preserve only non-bundled apps here.
    for app in "$legacy/apps/"*; do
        [ -d "$app" ] || continue
        name=${app##*/}
        if [ ! -d "/usr/src/nextcloud/apps/$name" ]; then
            rsync -rl "$app" "$base/custom_apps/"
        fi
    done
    test -s "$base/config/config.php"
    # Baseline verified: no old apps_paths entries or supplemental config files.
    cp /migration/apps.config.php "$base/config/zzz-official-apps.config.php"
    printf '%s\n' 'Prepared from preserved legacy installation' > "$base/.prepared"
fi
test -s "$base/config/config.php"

# This deletes stale ephemeral core files only; all persistent dirs are excluded.
rsync -rlD --delete --exclude-from=/upgrade.exclude /usr/src/nextcloud/ "$html/"
cp /usr/src/nextcloud/version.php "$html/version.php"
for dir in config custom_apps themes; do
    target="$base/$dir"
    if [ -L "$html/$dir" ]; then
        test "$(readlink "$html/$dir")" = "$target"
    else
        # Fail rather than remove an unexpected nonempty directory.
        if [ -d "$html/$dir" ]; then rmdir "$html/$dir"; fi
        ln -s "$target" "$html/$dir"
    fi
done
cp /migration/apps.config.php "$base/config/zzz-official-apps.config.php"
mkdir -p /data/.nginx-upload-cache
chmod 700 /data/.nginx-upload-cache

# Core version.php is already new, so stock entrypoint cannot perform this step.
php -d memory_limit=-1 "$html/occ" upgrade --no-interaction
php -d memory_limit=-1 "$html/occ" status --output=json
printf '%s\n' 'Official Nextcloud initialization and database upgrade completed'
