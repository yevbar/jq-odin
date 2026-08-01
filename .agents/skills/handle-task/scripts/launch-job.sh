#!/bin/sh
set -eu

# This launcher deliberately targets the Linux Vers runtime: process identities
# come from /proc, and state changes are serialized with util-linux flock(1).
# Every contender opens the same persistent lock file. Nobody unlinks or
# replaces it, and the kernel releases the advisory lock when its FD is closed
# or its process exits.
process_identity() {
    identity_pid=$1
    identity_start=$(
        sed 's/.*) //' "/proc/$identity_pid/stat" 2>/dev/null |
            awk '{ print $20 }'
    ) || identity_start=
    if [ -n "$identity_start" ]; then
        printf '%s:%s\n' "$identity_pid" "$identity_start"
    fi
}

identity_is_live() {
    expected_identity=$1
    identity_pid=${expected_identity%%:*}
    case "$identity_pid" in
        *[!0-9]*|'')
            return 1
            ;;
    esac
    [ "$(process_identity "$identity_pid")" = "$expected_identity" ]
}

read_identity() {
    identity_file=$1
    sed -n '/^[0-9][0-9]*:[0-9][0-9]*$/p' "$identity_file" 2>/dev/null |
        sed -n '$p'
}

# Durable runner records are stricter than owner records: they must be exactly
# one complete identity.
read_complete_identity() {
    identity_file=$1
    awk '
        NR == 1 && /^[0-9][0-9]*:[0-9][0-9]*$/ { identity = $0; next }
        { invalid = 1 }
        END { if (NR == 1 && !invalid) print identity }
    ' "$identity_file" 2>/dev/null || true
}

read_status() {
    status_path=$1
    sed -n '/^[0-9][0-9]*$/p' "$status_path" 2>/dev/null | sed -n '$p'
}

run_test_hook() {
    hook_point=$1
    if [ -n "${HANDLE_TASK_LAUNCH_TEST_HOOK:-}" ]; then
        sh "$HANDLE_TASK_LAUNCH_TEST_HOOK" "$hook_point"
    fi
}

lock_held=false
acquire_state_lock() {
    # FD 9 is process-local. It is closed on every release, including before
    # nohup/fork and before the durable child execs the runner.
    exec 9>>"$state_lock"
    lock_attempt=1
    while [ "$lock_attempt" -le "${HANDLE_TASK_LAUNCH_LOCK_ATTEMPTS:-100}" ]; do
        if "$flock_bin" -n 9; then
            lock_held=true
            run_test_hook after-state-lock-acquisition
            return 0
        fi
        lock_attempt=$((lock_attempt + 1))
        if [ "$lock_attempt" -le "${HANDLE_TASK_LAUNCH_LOCK_ATTEMPTS:-100}" ]; then
            sleep "${HANDLE_TASK_LAUNCH_LOCK_DELAY:-0.01}"
        fi
    done
    exec 9>&-
    echo "Unable to acquire launch-state lock after ${HANDLE_TASK_LAUNCH_LOCK_ATTEMPTS:-100} attempts: $state_lock" >&2
    return 1
}

release_state_lock() {
    if [ "$lock_held" = true ]; then
        "$flock_bin" -u 9
        lock_held=false
        exec 9>&-
    fi
}

flock_bin=${HANDLE_TASK_FLOCK_BIN:-flock}
if ! command -v "$flock_bin" >/dev/null 2>&1; then
    echo "Required Linux command not found: $flock_bin (install util-linux for flock)" >&2
    exit 1
fi

if [ "${1:-}" = --child ]; then
    shift
    expected_owner=${1:?expected launch owner is required}
    launch_marker=${2:?launch marker is required}
    runner_identity_file=${3:?runner identity file is required}
    runner=${4:?job runner is required}
    status_file=${5:?status file is required}
    job_log=${6:?job log is required}
    shift 6
    state_lock="${status_file}.launch-lock"

    # This is the durable child's first state-changing action. Revalidation and
    # runner identity publication share the state lock with recovery. If this
    # child was forked but not scheduled until after recovery, its old
    # generation no longer matches and it exits without running the job.
    run_test_hook child-before-pid-publication
    acquire_state_lock
    current_owner=$(read_identity "$launch_marker/owner")
    if [ "$current_owner" != "$expected_owner" ]; then
        release_state_lock
        exit 0
    fi
    runner_identity=$(process_identity "$$")
    if [ -z "$runner_identity" ]; then
        release_state_lock
        echo "Unable to identify durable runner: $$" >&2
        exit 1
    fi
    runner_identity_temp="${runner_identity_file}.tmp.$$"
    printf '%s\n' "$runner_identity" >"$runner_identity_temp"
    mv "$runner_identity_temp" "$runner_identity_file"
    release_state_lock
    run_test_hook child-after-pid-publication

    exec sh "$runner" "$status_file" "$job_log" "$@"
fi

launch_log=${1:?launch log is required}
runner=${2:?job runner is required}
status_file=${3:?status file is required}
job_log=${4:?job log is required}
shift 4

launch_marker="${status_file}.launch"
owner_file="$launch_marker/owner"
runner_identity_file="${status_file}.pid"
state_lock="${status_file}.launch-lock"
launcher_identity=$(process_identity "$$")
claim_owned=false

cleanup_uncommitted_claim() {
    cleanup_status=$?
    trap - EXIT HUP INT TERM
    release_state_lock
    if [ "$claim_owned" = true ] && acquire_state_lock; then
        cleanup_owner=$(read_identity "$owner_file")
        if [ ! -s "$runner_identity_file" ] && [ ! -s "$status_file" ] &&
           { [ -z "$cleanup_owner" ] ||
             [ "$cleanup_owner" = "$launcher_identity" ] ||
             ! identity_is_live "$cleanup_owner"; }; then
            rm -f "$owner_file"
            rmdir "$launch_marker" 2>/dev/null || true
        fi
        release_state_lock
    fi
    exit "$cleanup_status"
}
trap cleanup_uncommitted_claim EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

claim_state() {
    if [ -s "$status_file" ]; then
        completed_status=$(read_status "$status_file")
        if [ -n "$completed_status" ]; then
            printf '%s\n' completed
            return
        fi
    fi

    committed_runner=$(read_complete_identity "$runner_identity_file")
    if [ -n "$committed_runner" ]; then
        if identity_is_live "$committed_runner"; then
            printf '%s\n' runner-live
        else
            # Identity publication commits the one authoritative runner. A
            # dead committed runner is left for inspect-job.sh to report
            # rather than risking repetition of an arbitrary task.
            printf '%s\n' runner-committed
        fi
        return
    fi
    # A nonempty malformed record cannot establish liveness, but it still
    # proves a publication occurred. Fail closed instead of risking a second
    # durable runner; inspection reports the original runner gone.
    if [ -s "$runner_identity_file" ]; then
        printf '%s\n' runner-committed
        return
    fi

    observed_owner=$(read_identity "$owner_file")
    if [ -n "$observed_owner" ] && identity_is_live "$observed_owner"; then
        printf '%s\n' owner-live
    else
        printf '%s\n' stale
    fi
}

acquire_state_lock
initial_state=$(claim_state)
case "$initial_state" in
    completed|runner-live)
        release_state_lock
        claim_owned=false
        exit 0
        ;;
    runner-committed)
        release_state_lock
        claim_owned=false
        echo "Committed runner identity is no longer live" >&2
        exit 0
        ;;
esac

if [ -d "$launch_marker" ]; then
    # A dead/missing owner with no status or committed runner identity might
    # still have a forked child waiting to run. Observe for a bounded interval.
    # Recovery then replaces the generation under the state lock; any later
    # old child must validate that generation before it can publish or run.
    release_state_lock
    observe_attempt=1
    while [ "$observe_attempt" -le "${HANDLE_TASK_LAUNCH_OBSERVE_ATTEMPTS:-40}" ]; do
        sleep "${HANDLE_TASK_LAUNCH_OBSERVE_DELAY:-0.05}"
        acquire_state_lock
        observed_state=$(claim_state)
        case "$observed_state" in
            completed|runner-live)
                release_state_lock
                claim_owned=false
                exit 0
                ;;
            runner-committed)
                release_state_lock
                claim_owned=false
                echo "Committed runner identity is no longer live" >&2
                exit 0
                ;;
            owner-live)
                if [ "$observe_attempt" -eq "${HANDLE_TASK_LAUNCH_OBSERVE_ATTEMPTS:-40}" ]; then
                    release_state_lock
                    echo "Launch owner is still live without a committed runner identity" >&2
                    exit 1
                fi
                ;;
        esac
        observe_attempt=$((observe_attempt + 1))
        if [ "$observe_attempt" -le "${HANDLE_TASK_LAUNCH_OBSERVE_ATTEMPTS:-40}" ]; then
            release_state_lock
        fi
    done
fi

claim_owned=true
if [ ! -d "$launch_marker" ]; then
    mkdir "$launch_marker"
    run_test_hook after-claim-mkdir
fi
rm -f "$status_file" "$runner_identity_file"
owner_temp="$launch_marker/owner.tmp.$$"
printf '%s\n' "$launcher_identity" >"$owner_temp"
mv "$owner_temp" "$owner_file"
run_test_hook after-owner-publication
release_state_lock

run_test_hook before-fork
nohup sh "$0" --child "$launcher_identity" "$launch_marker" "$runner_identity_file" \
    "$runner" "$status_file" "$job_log" "$@" \
    </dev/null >"$launch_log" 2>&1 &
child_pid=$!
claim_owned=false
run_test_hook after-fork

# Complete runner identity publication is performed by the child. The launcher
# acknowledges success only after that commit. A timeout fails closed so the
# controller retries and uses the owner/generation recovery protocol instead
# of polling an unacknowledged job forever.
publish_attempt=1
while [ "$publish_attempt" -le "${HANDLE_TASK_LAUNCH_PUBLISH_ATTEMPTS:-100}" ]; do
    if [ -n "$(read_complete_identity "$runner_identity_file")" ] ||
       ! kill -0 "$child_pid" 2>/dev/null; then
        break
    fi
    sleep "${HANDLE_TASK_LAUNCH_PUBLISH_DELAY:-0.01}"
    publish_attempt=$((publish_attempt + 1))
done

if [ -z "$(read_complete_identity "$runner_identity_file")" ]; then
    if ! kill -0 "$child_pid" 2>/dev/null; then
        # The fork was acknowledged locally, but the child failed before
        # commit. Remove our uncommitted claim so the controller's bounded
        # retry can start a replacement immediately.
        claim_owned=true
        echo "Durable child exited before publishing its runner identity" >&2
    else
        # Preserve the generation while the child is still alive. Once this
        # launcher exits, a retry observes the now-dead owner before deciding
        # under the lock whether the late child or a replacement may commit.
        echo "Durable child did not publish its runner identity before launch timeout" >&2
    fi
    exit 1
fi
