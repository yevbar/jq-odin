#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/cleanup-vers-review-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

fake_bin="$test_dir/bin"
mkdir "$fake_bin"
cat >"$fake_bin/curl" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$FAKE_CURL_LOG"
printf '%s' "${FAKE_HTTP_STATUS:-204}"
EOF
chmod 755 "$fake_bin/curl"

vm_id_file="$test_dir/vm-id"
curl_log="$test_dir/curl.log"
printf '%s\n' 11111111-1111-4111-8111-111111111111 >"$vm_id_file"

PATH="$fake_bin:$PATH" \
FAKE_CURL_LOG="$curl_log" \
VERS_API_KEY=test-only \
    "$script_dir/cleanup-vers-review.sh" "$vm_id_file"
test ! -e "$vm_id_file"
grep -q '/vm/11111111-1111-4111-8111-111111111111' "$curl_log"

printf '%s\n' 22222222-2222-4222-8222-222222222222 >"$vm_id_file"
PATH="$fake_bin:$PATH" \
FAKE_CURL_LOG="$curl_log" \
FAKE_HTTP_STATUS=404 \
VERS_API_KEY=test-only \
    "$script_dir/cleanup-vers-review.sh" "$vm_id_file"
test ! -e "$vm_id_file"

printf '%s\n' not-a-vm >"$vm_id_file"
if PATH="$fake_bin:$PATH" \
    FAKE_CURL_LOG="$curl_log" \
    VERS_API_KEY=test-only \
    "$script_dir/cleanup-vers-review.sh" "$vm_id_file"; then
    echo "Expected an invalid VM ID to be rejected" >&2
    exit 1
fi
