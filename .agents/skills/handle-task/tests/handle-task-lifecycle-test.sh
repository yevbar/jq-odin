#!/bin/sh
set -eu

skill_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/handle-task-lifecycle-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

fake_vers="$test_dir/vers"
apply_log="$test_dir/vers.log"
inspect_count="$test_dir/inspect-count"
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
    exec)
        case "$*" in
            *"df -Pk /"*)
                echo 10485760
                ;;
            *"/tmp/handle-task-inspect-job.sh /run/handle-task/"*)
                count=0
                if [ -f "$VERS_INSPECT_COUNT" ]; then
                    count=$(cat "$VERS_INSPECT_COUNT")
                fi
                count=$((count + 1))
                printf '%s\n' "$count" >"$VERS_INSPECT_COUNT"
                if [ "${VERS_TEST_MODE:-success}" = codex-fail ] &&
                   [ "$count" -ge 2 ]; then
                    echo 1
                else
                    echo 0
                fi
                ;;
        esac
        ;;
    copy|resize|delete|pause)
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
    VERS_BIN="$fake_vers" \
        VERS_FAKE_LOG="$apply_log" \
        VERS_INSPECT_COUNT="$inspect_count" \
        VERS_TEST_MODE=${VERS_TEST_MODE:-success} \
        "$skill_dir/scripts/handle-task.sh" "$@"
}

run_launcher \
    --workstream facts \
    --task lifecycle-success \
    --prompt-file "$prompt_file"
grep -q '^delete -y 11111111-1111-4111-8111-111111111111$' "$apply_log"
! grep -q '^pause ' "$apply_log"

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

if VERS_TEST_MODE=create-disconnect run_launcher \
    --workstream facts \
    --task lifecycle-create-disconnect \
    --prompt-file "$prompt_file"; then
    echo "Expected the simulated run-commit disconnect to fail" >&2
    exit 1
fi
grep -q '^alias jq-facts-lifecycle-create-disconnect-' "$apply_log"
grep -q '^delete -y 11111111-1111-4111-8111-111111111111$' "$apply_log"
