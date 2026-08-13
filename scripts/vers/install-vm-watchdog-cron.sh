#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
watchdog="$script_dir/vm-watchdog.sh"
log_dir=${XDG_STATE_HOME:-$HOME/.local/state}/jq-experiment
mkdir -p "$log_dir"
touch "$log_dir/vm-watchdog.log"
chmod 700 "$watchdog" "$script_dir/vm-registry.sh"
entry="*/10 * * * * $watchdog >>$log_dir/vm-watchdog.log 2>&1"
existing=$(crontab -l 2>/dev/null || true)
filtered=$(printf '%s\n' "$existing" | grep -v -F "$watchdog" || true)
{ printf '%s\n' "$filtered"; printf '%s\n' "$entry"; } | crontab -
echo "installed jq-experiment Vers watchdog every 10 minutes"
