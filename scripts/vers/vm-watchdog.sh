#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$script_dir/vm-policy.env"
registry=${JQ_VERS_VM_REGISTRY:?missing registry path}
# Cron supplies a deliberately minimal PATH. Prefer the installed Vers CLI
# location so the watchdog still enforces the cap when launched unattended;
# callers can override it with VERS_BIN for tests or alternate installations.
vers_bin=${VERS_BIN:-/usr/local/bin/vers}
dry_run=false
[ "${1:-}" = --dry-run ] && dry_run=true

command -v "$vers_bin" >/dev/null 2>&1 || {
    echo "vm-watchdog: vers is not installed" >&2
    exit 1
}
command -v curl >/dev/null 2>&1 || { echo "vm-watchdog: curl is not installed" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "vm-watchdog: jq is not installed" >&2; exit 1; }

vers_config=${VERS_CONFIG:-$HOME/.versrc}
api_key=$(jq -er .apiKey "$vers_config")
vm_list=$(curl --fail --silent --show-error \
    -H "Authorization: Bearer $api_key" \
    "${VERS_API_BASE:-https://api.vers.sh/api/v1}/vms")

now=$(date +%s)
cutoff=$((now - JQ_VERS_VM_STALE_MINUTES * 60))
running=0
deleted=0
stale=0

if [ -f "$registry" ]; then
    tab=$(printf '\t')
    while IFS="$tab" read -r vm_id alias branch started; do
        [ -n "${vm_id:-}" ] || continue
        state=$(printf '%s\n' "$vm_list" | jq -r --arg id "$vm_id" \
            '.[] | select(.vm_id == $id) | .state' | head -n 1)
        if [ -z "$state" ] || [ "$state" = null ]; then
            # The VM was already deleted (possibly by a manual cleanup).
            "$script_dir/vm-registry.sh" unregister "$vm_id"
            continue
        fi
        case "$state" in
            running|booting)
                running=$((running + 1))
                ;;
            *)
                # Sleeping/paused workers are complete and must not consume
                # future launch capacity. Keep active VMs eligible for stale
                # deletion, but retire inactive registry rows.
                "$script_dir/vm-registry.sh" unregister "$vm_id"
                continue
                ;;
        esac
        if [ "${started:-0}" -le "$cutoff" ] && [ "$state" = running ]; then
            stale=$((stale + 1))
            if [ "$deleted" -lt "$JQ_VERS_VM_MAX_DELETIONS_PER_RUN" ]; then
                echo "vm-watchdog: stale project VM $vm_id ($alias, $branch)"
                if [ "$dry_run" = false ] && "$vers_bin" delete -y "$vm_id" >/dev/null 2>&1; then
                    "$script_dir/vm-registry.sh" unregister "$vm_id"
                    deleted=$((deleted + 1))
                fi
            fi
        fi
    done <"$registry"
fi

if [ "$running" -gt "$JQ_VERS_VM_MAX" ]; then
    echo "vm-watchdog: project worker count $running exceeds cap $JQ_VERS_VM_MAX" >&2
    exit 2
fi
echo "vm-watchdog: project running=$running cap=$JQ_VERS_VM_MAX stale=$stale deleted=$deleted"
