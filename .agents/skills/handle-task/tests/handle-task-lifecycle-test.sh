#!/bin/sh
set -eu

skill_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/handle-task-lifecycle-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

fake_vers="$test_dir/vers"
apply_log="$test_dir/vers.log"
inspect_count="$test_dir/inspect-count"
copy_count="$test_dir/copy-count"
remote_sizes="$test_dir/remote-sizes"
prompt_file="$test_dir/prompt.md"
printf '%s\n' "Implement the bounded test task." >"$prompt_file"

cat >"$fake_vers" <<'EOF'
#!/bin/sh
set -eu

printf '%s\n' "$*" >>"$VERS_FAKE_LOG"
command=$1
shift

case "$command" in
    run-commit)
        if [ "${VERS_TEST_MODE:-success}" = create-disconnect ]; then
            exit 1
        fi
        echo "VM '11111111-1111-4111-8111-111111111111' is running"
        ;;
    alias)
        echo 11111111-1111-4111-8111-111111111111
        ;;
    execute)
        case "$*" in
            *"df -Pk /"*)
                echo 10485760
                ;;
            *"wc -c"*"/tmp/handle-task-"*)
                remote_path=
                for argument do
                    remote_path=$argument
                done
                awk -v path="$remote_path" '
                    $1 == path { size=$2 }
                    END { if (size != "") print size }
                ' "$VERS_REMOTE_SIZES"
                ;;
            *"sh /tmp/handle-task-inspect-job.sh /run/handle-task/"*)
                count=0
                if [ -f "$VERS_INSPECT_COUNT" ]; then
                    count=$(cat "$VERS_INSPECT_COUNT")
                fi
                count=$((count + 1))
                printf '%s\n' "$count" >"$VERS_INSPECT_COUNT"
                if { [ "${VERS_TEST_MODE:-success}" = codex-fail ] ||
                     [ "${VERS_TEST_MODE:-success}" = pause-fail ]; } &&
                   [ "$count" -ge 2 ]; then
                    echo 1
                elif [ "${VERS_TEST_MODE:-success}" = prepare-fail ]; then
                    echo 1
                else
                    echo 0
                fi
                ;;
        esac
        ;;
    copy)
        shift 3
        source_path=$1
        remote_path=$2
        count=0
        if [ -f "$VERS_COPY_COUNT" ]; then
            count=$(cat "$VERS_COPY_COUNT")
        fi
        count=$((count + 1))
        printf '%s\n' "$count" >"$VERS_COPY_COUNT"
        size=$(wc -c <"$source_path" | tr -d '[:space:]')
        if [ "${VERS_TEST_MODE:-success}" = copy-retry ] &&
           [ "$count" -eq 1 ]; then
            size=0
        fi
        printf '%s %s\n' "$remote_path" "$size" >>"$VERS_REMOTE_SIZES"
        ;;
    pause)
        if [ "${VERS_TEST_MODE:-success}" = pause-fail ]; then
            exit 1
        fi
        ;;
    resize|delete)
        ;;
    *)
        echo "Unexpected fake Vers command: $command" >&2
        exit 1
        ;;
esac
EOF
chmod 755 "$fake_vers"

run_launcher() {
    : >"$apply_log"
    rm -f "$inspect_count"
    rm -f "$copy_count" "$remote_sizes"
    : >"$remote_sizes"
    VERS_BIN="$fake_vers" \
        VERS_FAKE_LOG="$apply_log" \
        VERS_INSPECT_COUNT="$inspect_count" \
        VERS_COPY_COUNT="$copy_count" \
        VERS_REMOTE_SIZES="$remote_sizes" \
        VERS_TEST_MODE=${VERS_TEST_MODE:-success} \
        HANDLE_TASK_COPY_RETRY_DELAY=0 \
        "$skill_dir/scripts/handle-task.sh" "$@"
}

GITHUB_API_KEY=credential-must-not-appear run_launcher \
    --workstream facts \
    --task lifecycle-success \
    --prompt-file "$prompt_file"
grep -q '^delete -y 11111111-1111-4111-8111-111111111111$' "$apply_log"
! grep -q '^pause ' "$apply_log"
! grep -q 'credential-must-not-appear' "$apply_log"
grep -q '^execute -t 60 11111111-1111-4111-8111-111111111111 ' "$apply_log"
! grep -q '^exec ' "$apply_log"

# The first SFTP result is truncated. The launcher must verify its byte count,
# retry it, and continue through later copies without function assignments
# clobbering the top-level Vers executable or command state.
VERS_TEST_MODE=copy-retry run_launcher \
    --workstream facts \
    --task lifecycle-copy-retry \
    --prepare-only
test "$(grep -c '^copy .* /tmp/handle-task-prepare-vm.sh$' "$apply_log")" = 2
grep -q '^copy .* /tmp/handle-task-run-job.sh$' "$apply_log"
grep -q '^copy .* /tmp/handle-task-launch-job.sh$' "$apply_log"
grep -q '^copy .* /tmp/handle-task-inspect-job.sh$' "$apply_log"
grep -q 'execute .* sh /tmp/handle-task-launch-job.sh ' "$apply_log"
! grep -q '^delete ' "$apply_log"

run_launcher \
    --workstream facts \
    --task lifecycle-interactive \
    --prepare-only
! grep -q '^delete ' "$apply_log"
! grep -q '^pause ' "$apply_log"

run_launcher \
    --workstream facts \
    --task lifecycle-kept \
    --prompt-file "$prompt_file" \
    --keep-vm
! grep -q '^delete ' "$apply_log"
! grep -q '^pause ' "$apply_log"

if VERS_TEST_MODE=codex-fail run_launcher \
    --workstream facts \
    --task lifecycle-failure \
    --prompt-file "$prompt_file"; then
    echo "Expected the simulated Codex task to fail" >&2
    exit 1
fi
grep -q '^pause 11111111-1111-4111-8111-111111111111$' "$apply_log"
! grep -q '^delete ' "$apply_log"

if VERS_TEST_MODE=prepare-fail run_launcher \
    --workstream facts \
    --task lifecycle-prepare-failure \
    --prompt-file "$prompt_file"; then
    echo "Expected the simulated preparation to fail" >&2
    exit 1
fi
grep -q '^pause 11111111-1111-4111-8111-111111111111$' "$apply_log"
! grep -q '^delete ' "$apply_log"

if VERS_TEST_MODE=pause-fail run_launcher \
    --workstream facts \
    --task lifecycle-pause-failure \
    --prompt-file "$prompt_file"; then
    echo "Expected the simulated Codex and pause operations to fail" >&2
    exit 1
fi
grep -q '^pause 11111111-1111-4111-8111-111111111111$' "$apply_log"
! grep -q '^delete ' "$apply_log"

if VERS_TEST_MODE=create-disconnect run_launcher \
    --workstream facts \
    --task lifecycle-create-disconnect \
    --prompt-file "$prompt_file"; then
    echo "Expected the simulated run-commit disconnect to fail" >&2
    exit 1
fi
grep -q '^alias jq-facts-lifecycle-create-disconnect-' "$apply_log"
grep -q '^pause 11111111-1111-4111-8111-111111111111$' "$apply_log"
! grep -q '^delete ' "$apply_log"
