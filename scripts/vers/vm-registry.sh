#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$script_dir/vm-policy.env"
registry=${JQ_VERS_VM_REGISTRY:?missing registry path}
command=${1:-}
mkdir -p "$(dirname -- "$registry")"

case "$command" in
    register)
        [ "$#" -eq 4 ] || { echo "usage: vm-registry.sh register VM_ID ALIAS BRANCH" >&2; exit 2; }
        vm_id=$2
        case "$vm_id" in *[!a-f0-9-]*|'') echo "invalid VM id" >&2; exit 2;; esac
        lock="$registry.lock"
        while ! mkdir "$lock" 2>/dev/null; do sleep 1; done
        trap 'rmdir "$lock" 2>/dev/null || true' EXIT HUP INT TERM
        touch "$registry"
        awk -F '\t' -v id="$vm_id" '$1 != id' "$registry" >"$registry.tmp"
        printf '%s\t%s\t%s\t%s\n' "$vm_id" "$3" "$4" "$(date +%s)" >>"$registry.tmp"
        mv "$registry.tmp" "$registry"
        ;;
    unregister)
        [ "$#" -eq 2 ] || { echo "usage: vm-registry.sh unregister VM_ID" >&2; exit 2; }
        [ -f "$registry" ] || exit 0
        lock="$registry.lock"
        while ! mkdir "$lock" 2>/dev/null; do sleep 1; done
        trap 'rmdir "$lock" 2>/dev/null || true' EXIT HUP INT TERM
        awk -F '\t' -v id="$2" '$1 != id' "$registry" >"$registry.tmp"
        mv "$registry.tmp" "$registry"
        ;;
    list)
        [ -f "$registry" ] && cat "$registry"
        ;;
    *)
        echo "usage: vm-registry.sh {register|unregister|list} ..." >&2
        exit 2
        ;;
esac
