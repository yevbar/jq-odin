#!/bin/sh
set -eu

default_commit=13b7c648-7849-4b9b-a788-16b4522edeb8
api_base=${VERS_API_BASE:-https://api.vers.sh/api/v1}
commit_id=${VERS_REVIEW_COMMIT:-$default_commit}

usage() {
    cat <<'EOF'
Usage: run-vers-review.sh PACKET_DIR RESULT_FILE

Restore the approved authenticated Codex snapshot, upload the diff-only review
packet, run the reviewer, download its JSON assessment, and delete the VM.

Environment:
  VERS_API_KEY        Required Vers bearer token
  VERS_REVIEW_COMMIT  Approved Vers commit UUID
  VERS_API_BASE       API override for controller tests
EOF
}

if [ "$#" -ne 2 ]; then
    usage >&2
    exit 2
fi

packet_dir=$1
result_file=$2
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
vm_script="$script_dir/vers-review-vm.sh"
cleanup_script="$script_dir/cleanup-vers-review.sh"
vm_id_file=${VERS_VM_ID_FILE:-"$(dirname -- "$result_file")/vers-vm-id"}
vm_id=
upload_tmp_dir=
auth_header_file=

if [ -z "${VERS_API_KEY:-}" ]; then
    echo "VERS_API_KEY is required" >&2
    exit 1
fi

for dependency in curl jq base64; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        echo "Required command not found: $dependency" >&2
        exit 1
    fi
done

for file in manifest.txt files.tsv change.diff PROMPT.md result.schema.json; do
    if [ ! -f "$packet_dir/$file" ]; then
        echo "Review packet is missing $file" >&2
        exit 1
    fi
done

api() {
    method=$1
    endpoint=$2
    body=${3-}

    if [ -n "$body" ]; then
        curl --fail-with-body --silent --show-error \
            -X "$method" \
            -H "@$auth_header_file" \
            -H "Content-Type: application/json" \
            --data "$body" \
            "$api_base$endpoint"
    else
        curl --fail-with-body --silent --show-error \
            -X "$method" \
            -H "@$auth_header_file" \
            "$api_base$endpoint"
    fi
}

api_retry() {
    method=$1
    endpoint=$2
    body=${3-}

    if [ -n "$body" ]; then
        curl --fail-with-body --silent --show-error \
            --retry 5 --retry-all-errors \
            -X "$method" \
            -H "@$auth_header_file" \
            -H "Content-Type: application/json" \
            --data "$body" \
            "$api_base$endpoint"
    else
        curl --fail-with-body --silent --show-error \
            --retry 5 --retry-all-errors \
            -X "$method" \
            -H "@$auth_header_file" \
            "$api_base$endpoint"
    fi
}

cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    if [ -n "$upload_tmp_dir" ]; then
        rm -rf "$upload_tmp_dir"
    fi
    if [ -n "$vm_id" ]; then
        if ! VERS_API_BASE="$api_base" "$cleanup_script" "$vm_id_file"; then
            echo "Failed to delete review VM $vm_id" >&2
            status=1
        fi
    fi
    exit "$status"
}
trap cleanup EXIT HUP INT TERM

api_retry_file() {
    method=$1
    endpoint=$2
    body_file=$3

    curl --fail-with-body --silent --show-error \
        --retry 5 --retry-all-errors \
        -X "$method" \
        -H "@$auth_header_file" \
        -H "Content-Type: application/json" \
        --data-binary "@$body_file" \
        "$api_base$endpoint"
}

upload_file() {
    local_file=$1
    remote_file=$2
    mode=$3
    encoded_file="$upload_tmp_dir/content.b64"
    body_file="$upload_tmp_dir/request.json"

    base64 <"$local_file" | tr -d '\n' >"$encoded_file"
    jq -cn \
        --arg path "$remote_file" \
        --rawfile content "$encoded_file" \
        --argjson mode "$mode" \
        '{path: $path, content_b64: $content, create_dirs: true, mode: $mode}' \
        >"$body_file"
    api_retry_file PUT "/vm/$vm_id/files" "$body_file" >/dev/null
}

upload_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/vers-review-upload.XXXXXX")
auth_header_file="$upload_tmp_dir/auth-header"
printf 'Authorization: Bearer %s\n' "$VERS_API_KEY" >"$auth_header_file"
chmod 600 "$auth_header_file"

echo "Restoring approved Vers review snapshot $commit_id"
create_body=$(jq -cn --arg id "$commit_id" '{commit_id: $id}')
create_response=$(api POST /vm/from_commit "$create_body")
vm_id=$(printf '%s\n' "$create_response" | jq -er .vm_id)
mkdir -p "$(dirname -- "$vm_id_file")"
printf '%s\n' "$vm_id" >"$vm_id_file"
echo "Review VM: $vm_id"

attempt=0
while :; do
    state=$(api_retry GET "/vm/$vm_id/status" | jq -er .state)
    case "$state" in
        running)
            break
            ;;
        booting)
            attempt=$((attempt + 1))
            if [ "$attempt" -ge 60 ]; then
                echo "Review VM did not become ready" >&2
                exit 1
            fi
            sleep 2
            ;;
        *)
            echo "Review VM entered unexpected state: $state" >&2
            exit 1
            ;;
    esac
done

for file in manifest.txt files.tsv change.diff PROMPT.md result.schema.json; do
    upload_file "$packet_dir/$file" "/tmp/jq-review/$file" 420
done
upload_file "$vm_script" /tmp/jq-review/run-review.sh 493

echo "Running authenticated Codex reviewer in the disposable VM"
exec_body=$(
    jq -cn '{
        command: [
            "sh",
            "-c",
            "nohup /tmp/jq-review/run-review.sh >/tmp/jq-review/review.log 2>&1 </dev/null &"
        ],
        env: {
            HOME: "/root",
            CODEX_HOME: "/root/.codex"
        },
        timeout_secs: 30,
        working_dir: "/tmp/jq-review"
    }'
)
exec_response=$(api POST "/vm/$vm_id/exec" "$exec_body")
if [ "$(printf '%s' "$exec_response" | jq -er .exit_code)" -ne 0 ]; then
    printf '%s' "$exec_response" | jq -r '.stderr' >&2
    echo "Unable to launch the Vers reviewer" >&2
    exit 1
fi

poll_body=$(
    jq -cn '{
        command: [
            "sh",
            "-c",
            "if test -f /tmp/jq-review/exit-code; then cat /tmp/jq-review/exit-code; else exit 3; fi"
        ],
        timeout_secs: 30,
        working_dir: "/tmp/jq-review"
    }'
)
attempt=0
while :; do
    # This exec only reads a completion marker, so retrying it is safe.
    poll_response=$(api_retry POST "/vm/$vm_id/exec" "$poll_body")
    poll_exit=$(printf '%s' "$poll_response" | jq -er .exit_code)
    case "$poll_exit" in
        0)
            review_exit=$(
                printf '%s' "$poll_response" |
                    jq -er '.stdout | gsub("[[:space:]]"; "")'
            )
            break
            ;;
        3)
            attempt=$((attempt + 1))
            if [ "$attempt" -ge 180 ]; then
                echo "Vers reviewer exceeded 30 minutes" >&2
                exit 1
            fi
            sleep 10
            ;;
        *)
            printf '%s' "$poll_response" | jq -r '.stderr' >&2
            echo "Unable to poll the Vers reviewer" >&2
            exit 1
            ;;
    esac
done

if [ "$review_exit" -ne 0 ]; then
    log_response=$(
        curl --fail-with-body --silent --show-error \
            --retry 3 --retry-all-errors \
            -G \
            -H "@$auth_header_file" \
            --data-urlencode path=/tmp/jq-review/review.log \
            "$api_base/vm/$vm_id/files"
    )
    printf '%s' "$log_response" | jq -er .content_b64 |
        base64 --decode 2>/dev/null ||
        printf '%s' "$log_response" | jq -er .content_b64 | base64 -D
    echo "Vers reviewer command failed with exit $review_exit" >&2
    exit 1
fi

mkdir -p "$(dirname -- "$result_file")"
read_response=$(
    curl --fail-with-body --silent --show-error \
        --retry 3 --retry-all-errors \
        -G \
        -H "@$auth_header_file" \
        --data-urlencode path=/tmp/jq-review/result.json \
        "$api_base/vm/$vm_id/files"
)
encoded_result=$(printf '%s' "$read_response" | jq -er .content_b64)
if printf '%s' "$encoded_result" | base64 --decode >"$result_file" 2>/dev/null; then
    :
else
    printf '%s' "$encoded_result" | base64 -D >"$result_file"
fi

jq -e . "$result_file" >/dev/null
echo "Assessment downloaded to $result_file"
