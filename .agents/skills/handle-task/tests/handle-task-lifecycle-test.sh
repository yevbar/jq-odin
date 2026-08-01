#!/bin/sh
set -eu

skill_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/handle-task-lifecycle-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

fake_vers="$test_dir/vers"
apply_log="$test_dir/vers.log"
copy_count="$test_dir/copy-count"
remote_sizes="$test_dir/remote-sizes"
vers_state_dir="$test_dir/vers-state"
prompt_file="$test_dir/prompt.md"
printf '%s\n' "Implement the bounded test task." >"$prompt_file"
mkdir "$vers_state_dir"

cat >"$fake_vers" <<'EOF'
#!/bin/sh
set -eu

printf '%s\n' "$*" >>"$VERS_FAKE_LOG"
command=$1
shift

increment_file() {
    increment_path=$1
    increment_value=0
    if [ -f "$increment_path" ]; then
        increment_value=$(cat "$increment_path")
    fi
    increment_value=$((increment_value + 1))
    printf '%s\n' "$increment_value" >"$increment_path"
}

job_name_for_status() {
    case "$1" in
        */prepare.status)
            printf '%s\n' prepare
            ;;
        */codex.status)
            printf '%s\n' codex
            ;;
        *)
            echo "Unexpected status path: $1" >&2
            exit 1
            ;;
    esac
}

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
        if [ "${5:-}" = /tmp/handle-task-launch-job.sh ]; then
            launch_status=${8:?launch status is required}
            launch_job=$(job_name_for_status "$launch_status")
            launch_attempts="$VERS_STATE_DIR/$launch_job.launch-attempts"
            increment_file "$launch_attempts"
            launch_attempt=$(cat "$launch_attempts")

            if [ "${VERS_TEST_MODE:-success}" = launch-disconnect-before-start ] &&
               [ "$launch_attempt" -eq 1 ]; then
                exit 1
            fi

            launch_marker="$VERS_STATE_DIR/$launch_job.status.launch"
            if [ "${VERS_TEST_MODE:-success}" = launch-owner-dies-before-commit ]; then
                mkdir -p "$launch_marker"
                if [ "$launch_attempt" -le 2 ]; then
                    if [ "$launch_attempt" -eq 2 ]; then
                        touch "$VERS_STATE_DIR/$launch_job.owner-live-observed"
                    fi
                    exit 1
                fi
                increment_file "$VERS_STATE_DIR/$launch_job.runner-count"
                printf '%s:%s\n' "$((4100 + launch_attempt))" 1 >"$VERS_STATE_DIR/$launch_job.status.pid"
                printf '%s\n' 0 >"$VERS_STATE_DIR/$launch_job.status"
                exit 0
            fi

            if [ "${VERS_TEST_MODE:-success}" = launch-owner-stuck ]; then
                mkdir -p "$launch_marker"
                touch "$VERS_STATE_DIR/$launch_job.owner-live-observed"
                exit 1
            fi

            if mkdir "$launch_marker" 2>/dev/null; then
                increment_file "$VERS_STATE_DIR/$launch_job.runner-count"
                printf '%s:%s\n' "$((4100 + launch_attempt))" 1 >"$VERS_STATE_DIR/$launch_job.status.pid"
                launch_status_value=0
                if { [ "${VERS_TEST_MODE:-success}" = codex-fail ] ||
                     [ "${VERS_TEST_MODE:-success}" = pause-fail ]; } &&
                   [ "$launch_job" = codex ]; then
                    launch_status_value=23
                elif [ "${VERS_TEST_MODE:-success}" = prepare-fail ] &&
                     [ "$launch_job" = prepare ]; then
                    launch_status_value=19
                fi
                printf '%s\n' "$launch_status_value" >"$VERS_STATE_DIR/$launch_job.status"
            fi

            if [ "${VERS_TEST_MODE:-success}" = launch-disconnect-after-start ] &&
               [ "$launch_attempt" -eq 1 ]; then
                exit 1
            fi
            exit 0
        fi

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
                inspect_status=${6:?inspection status is required}
                inspect_job=$(job_name_for_status "$inspect_status")
                cat "$VERS_STATE_DIR/$inspect_job.status"
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
    rm -f "$copy_count" "$remote_sizes"
    rm -rf "$vers_state_dir"
    mkdir "$vers_state_dir"
    : >"$remote_sizes"
    VERS_BIN="$fake_vers" \
        VERS_FAKE_LOG="$apply_log" \
        VERS_COPY_COUNT="$copy_count" \
        VERS_REMOTE_SIZES="$remote_sizes" \
        VERS_STATE_DIR="$vers_state_dir" \
        VERS_TEST_MODE=${VERS_TEST_MODE:-success} \
        HANDLE_TASK_COPY_RETRY_DELAY=0 \
        HANDLE_TASK_LAUNCH_RETRY_DELAY=0 \
        "$skill_dir/scripts/handle-task.sh" "$@"
}

assert_runner_identity_file() {
    identity_path=$1
    test "$(wc -l <"$identity_path" | tr -d '[:space:]')" = 1
    grep -Eq '^[0-9]+:[0-9]+$' "$identity_path"
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
test -d "$vers_state_dir/prepare.status.launch"
test -d "$vers_state_dir/codex.status.launch"
test "$(cat "$vers_state_dir/prepare.runner-count")" = 1
test "$(cat "$vers_state_dir/codex.runner-count")" = 1
test "$(cat "$vers_state_dir/prepare.status")" = 0
test "$(cat "$vers_state_dir/codex.status")" = 0
test -s "$vers_state_dir/prepare.status.pid"
test -s "$vers_state_dir/codex.status.pid"
assert_runner_identity_file "$vers_state_dir/prepare.status.pid"
assert_runner_identity_file "$vers_state_dir/codex.status.pid"
grep -q 'runuser -u jqagent -- env HOME=/home/jqagent sh /tmp/handle-task-run-codex.sh ' "$apply_log"

# A lost acknowledgement after each remote launch has started is retried. The
# status-specific marker makes both retries no-ops, leaving one authoritative
# preparation runner and one authoritative Codex runner.
VERS_TEST_MODE=launch-disconnect-after-start run_launcher \
    --workstream facts \
    --task lifecycle-launch-disconnect-after \
    --prompt-file "$prompt_file"
test "$(cat "$vers_state_dir/prepare.launch-attempts")" = 2
test "$(cat "$vers_state_dir/codex.launch-attempts")" = 2
test "$(cat "$vers_state_dir/prepare.runner-count")" = 1
test "$(cat "$vers_state_dir/codex.runner-count")" = 1
test "$(cat "$vers_state_dir/prepare.status")" = 0
test "$(cat "$vers_state_dir/codex.status")" = 0
test -s "$vers_state_dir/prepare.status.pid"
test -s "$vers_state_dir/codex.status.pid"
assert_runner_identity_file "$vers_state_dir/prepare.status.pid"
assert_runner_identity_file "$vers_state_dir/codex.status.pid"

# A disconnect before the remote command starts leaves no marker. The retry
# claims it and starts exactly one runner for both durable job paths.
VERS_TEST_MODE=launch-disconnect-before-start run_launcher \
    --workstream facts \
    --task lifecycle-launch-disconnect-before \
    --prompt-file "$prompt_file"
test "$(cat "$vers_state_dir/prepare.launch-attempts")" = 2
test "$(cat "$vers_state_dir/codex.launch-attempts")" = 2
test "$(cat "$vers_state_dir/prepare.runner-count")" = 1
test "$(cat "$vers_state_dir/codex.runner-count")" = 1
test -d "$vers_state_dir/prepare.status.launch"
test -d "$vers_state_dir/codex.status.launch"

# The first call loses its acknowledgement before commit. Its retry observes
# only a live owner and also fails; after that owner dies, the final bounded
# attempt recovers and commits exactly one runner. The controller must not
# treat either uncommitted attempt as success.
VERS_TEST_MODE=launch-owner-dies-before-commit run_launcher \
    --workstream facts \
    --task lifecycle-owner-dies-before-commit \
    --prompt-file "$prompt_file"
test "$(cat "$vers_state_dir/prepare.launch-attempts")" = 3
test "$(cat "$vers_state_dir/codex.launch-attempts")" = 3
test -e "$vers_state_dir/prepare.owner-live-observed"
test -e "$vers_state_dir/codex.owner-live-observed"
test "$(cat "$vers_state_dir/prepare.runner-count")" = 1
test "$(cat "$vers_state_dir/codex.runner-count")" = 1
test -s "$vers_state_dir/prepare.status.pid"
test -s "$vers_state_dir/codex.status.pid"
assert_runner_identity_file "$vers_state_dir/prepare.status.pid"
assert_runner_identity_file "$vers_state_dir/codex.status.pid"

# A permanently live, uncommitted owner exhausts the three controller launch
# attempts and fails before wait_for_remote_job can poll "starting" forever.
if VERS_TEST_MODE=launch-owner-stuck run_launcher \
    --workstream facts \
    --task lifecycle-owner-stuck \
    --prompt-file "$prompt_file"; then
    echo "Expected permanently uncommitted launch owner to fail" >&2
    exit 1
fi
test "$(cat "$vers_state_dir/prepare.launch-attempts")" = 3
test -e "$vers_state_dir/prepare.owner-live-observed"
test ! -e "$vers_state_dir/prepare.runner-count"
test ! -e "$vers_state_dir/prepare.status.pid"
! grep -q 'sh /tmp/handle-task-inspect-job.sh' "$apply_log"
grep -q '^pause 11111111-1111-4111-8111-111111111111$' "$apply_log"

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
test "$(cat "$vers_state_dir/codex.status")" = 23
test "$(cat "$vers_state_dir/codex.runner-count")" = 1

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
