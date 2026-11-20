#!/bin/sh
set -eu
child=''
stop() {
    if [ -n "$child" ]; then
        kill -TERM "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
    fi
    exit 0
}
trap stop TERM INT
php /migration/check-runtime.php
while :; do
    php -d memory_limit=-1 -f /var/www/html/cron.php &
    child=$!
    if wait "$child"; then
        printf '%s\n' 'NEXTCLOUD_CRON_CYCLE_SUCCEEDED'
    else
        printf '%s\n' 'NEXTCLOUD_CRON_CYCLE_FAILED' >&2
    fi
    sleep 300 &
    child=$!
    wait "$child" || true
done
