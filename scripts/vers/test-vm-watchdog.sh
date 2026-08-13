#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/jq-vm-watchdog-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

bin="$tmp/bin"
mkdir -p "$bin" "$tmp/state"
cat >"$tmp/config.json" <<'EOF'
{"apiKey":"test"}
EOF
cat >"$bin/curl" <<'EOF'
#!/bin/sh
cat "$VM_WATCHDOG_FIXTURE"
EOF
cat >"$bin/vers" <<'EOF'
#!/bin/sh
if [ "${1:-}" = delete ]; then
    printf '%s\n' "$2" >>"$VM_WATCHDOG_DELETES"
    exit 0
fi
exit 0
EOF
chmod 755 "$bin/curl" "$bin/vers"

now=$(date +%s)
old=$((now - 7 * 3600))
cat >"$tmp/vms.json" <<EOF
[
  {"vm_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","owner_id":"owner","state":"running","created_at":"1970-01-01T00:00:00Z","labels":{"name":"old-1"}},
  {"vm_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","owner_id":"owner","state":"running","created_at":"1970-01-01T00:00:00Z","labels":{"name":"old-2"}},
  {"vm_id":"cccccccc-cccc-cccc-cccc-cccccccccccc","owner_id":"owner","state":"running","created_at":"1970-01-01T00:00:00Z","labels":{"name":"old-3"}},
  {"vm_id":"dddddddd-dddd-dddd-dddd-dddddddddddd","owner_id":"owner","state":"running","created_at":"1970-01-01T00:00:00Z","labels":{"name":"old-4"}},
  {"vm_id":"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee","owner_id":"owner","state":"running","created_at":"2030-01-01T00:00:00Z","labels":{"name":"new"}}
]
EOF

export PATH="$bin:$PATH"
export VERS_BIN="$bin/vers"
export VERS_CONFIG="$tmp/config.json"
export VERS_API_BASE=https://example.invalid/api/v1
export VM_WATCHDOG_FIXTURE="$tmp/vms.json"
export VM_WATCHDOG_DELETES="$tmp/deletes"
export JQ_VERS_VM_REGISTRY="$tmp/state/vers-vms.tsv"
export JQ_VERS_VM_MAX=16
export JQ_VERS_VM_STALE_MINUTES=360
export JQ_VERS_VM_MAX_DELETIONS_PER_RUN=3

output=$(/bin/sh "$root/scripts/vers/vm-watchdog.sh" --dry-run 2>&1)
printf '%s\n' "$output" | grep -q 'stale legacy VM aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' || exit 1
printf '%s\n' "$output" | grep -q 'stale=3 deleted=0' || exit 1

output=$(/bin/sh "$root/scripts/vers/vm-watchdog.sh" 2>&1)
[ "$(wc -l <"$tmp/deletes" | tr -d ' ')" -eq 3 ] || exit 1

echo 'vm-watchdog empty-registry recovery test passed'
