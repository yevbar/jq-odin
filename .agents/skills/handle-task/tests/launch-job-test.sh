#!/bin/sh
set -eu

skill_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/handle-task-launch-test.XXXXXX")
durable_pid=
cleanup() {
    if [ -n "$durable_pid" ]; then
        kill "$durable_pid" 2>/dev/null || true
    fi
    rm -rf "$test_dir"
}
trap cleanup EXIT HUP INT TERM

payload="literal'; touch $test_dir/injected; #"
status_file="$test_dir/status"
job_log="$test_dir/job.log"
launch_log="$test_dir/launch.log"
runner="$test_dir/run-job.sh"
cp "$skill_dir/scripts/run-job.sh" "$runner"
chmod 600 "$runner"

hook_script="$test_dir/launch-hook.sh"
cat >"$hook_script" <<'EOF'
#!/bin/sh
set -eu
point=${1:?hook point is required}
hook_parent=$PPID
touch "$LAUNCH_HOOK_DIR/$point.entered"
case ",${LAUNCH_HOOK_FAIL_POINTS:-}," in
    *",$point,"*)
        exit 71
        ;;
esac
case ",${LAUNCH_HOOK_BLOCK_POINTS:-}," in
    *",$point,"*)
        while [ ! -e "$LAUNCH_HOOK_DIR/$point.release" ]; do
            if ! kill -0 "$hook_parent" 2>/dev/null; then
                exit 72
            fi
            sleep 0.01
        done
        ;;
esac
EOF
chmod 700 "$hook_script"

wait_for_path() {
    wait_path=$1
    wait_attempt=0
    while [ ! -e "$wait_path" ] && [ "$wait_attempt" -lt 500 ]; do
        sleep 0.01
        wait_attempt=$((wait_attempt + 1))
    done
    test -e "$wait_path"
}

wait_for_status() {
    wait_status=$1
    wait_attempt=0
    while [ ! -s "$wait_status" ] && [ "$wait_attempt" -lt 500 ]; do
        sleep 0.01
        wait_attempt=$((wait_attempt + 1))
    done
    test -s "$wait_status"
}

assert_single_success() {
    assert_status=$1
    assert_count=$2
    wait_for_status "$assert_status"
    test "$(cat "$assert_status")" = 0
    test "$(wc -l <"$assert_count" | tr -d '[:space:]')" = 1
}

process_identity() {
    assert_pid=$1
    assert_start=$(
        sed 's/.*) //' "/proc/$assert_pid/stat" 2>/dev/null |
            awk '{ print $20 }'
    ) || assert_start=
    if [ -n "$assert_start" ]; then
        printf '%s:%s\n' "$assert_pid" "$assert_start"
    fi
}

assert_live_identity() {
    assert_identity=$1
    assert_pid=${assert_identity%%:*}
    test "$(process_identity "$assert_pid")" = "$assert_identity"
}

if HANDLE_TASK_FLOCK_BIN=handle-task-test-missing-flock \
    "$skill_dir/scripts/launch-job.sh" 2>"$test_dir/missing-flock.err"; then
    echo "Expected a missing flock dependency to fail" >&2
    exit 1
fi
grep -q '^Required Linux command not found: handle-task-test-missing-flock ' \
    "$test_dir/missing-flock.err"

test_pre_fork_recovery() {
    recovery_name=$1
    recovery_point=$2
    recovery_dir="$test_dir/$recovery_name"
    recovery_status="$recovery_dir/status"
    recovery_count="$recovery_dir/count"
    mkdir "$recovery_dir"

    LAUNCH_HOOK_DIR="$recovery_dir" \
    LAUNCH_HOOK_BLOCK_POINTS="$recovery_point" \
    HANDLE_TASK_LAUNCH_TEST_HOOK="$hook_script" \
    HANDLE_TASK_LAUNCH_OBSERVE_ATTEMPTS=2 \
    HANDLE_TASK_LAUNCH_OBSERVE_DELAY=0.01 \
        "$skill_dir/scripts/launch-job.sh" \
        "$recovery_dir/launch.log" "$runner" \
        "$recovery_status" "$recovery_dir/job.log" \
        sh -c 'printf "%s\n" started >>"$1"' sh "$recovery_count" &
    recovery_launcher=$!
    wait_for_path "$recovery_dir/$recovery_point.entered"
    recovery_lock="${recovery_status}.launch-lock"
    test -f "$recovery_lock"
    recovery_lock_inode=$(stat -Lc '%d:%i' "$recovery_lock")
    if [ "$recovery_point" = before-fork ]; then
        # The parent has closed its lock FD before the fork boundary.
        flock -n "$recovery_lock" true
    fi
    kill -KILL "$recovery_launcher"
    wait "$recovery_launcher" 2>/dev/null || true

    HANDLE_TASK_LAUNCH_OBSERVE_ATTEMPTS=2 \
    HANDLE_TASK_LAUNCH_OBSERVE_DELAY=0.01 \
        "$skill_dir/scripts/launch-job.sh" \
        "$recovery_dir/retry.log" "$runner" \
        "$recovery_status" "$recovery_dir/job.log" \
        sh -c 'printf "%s\n" started >>"$1"' sh "$recovery_count"
    assert_single_success "$recovery_status" "$recovery_count"
    test "$(stat -Lc '%d:%i' "$recovery_lock")" = "$recovery_lock_inode"
}

test_kernel_lock_interruption() {
    lock_iteration=$1
    lock_dir="$test_dir/kernel-lock-interruption-$lock_iteration"
    lock_status="$lock_dir/status"
    lock_path="${lock_status}.launch-lock"
    lock_count="$lock_dir/count"
    lock_release="$lock_dir/runner.release"
    lock_a_hooks="$lock_dir/a-hooks"
    lock_b_hooks="$lock_dir/b-hooks"
    lock_c_hooks="$lock_dir/c-hooks"
    mkdir -p "$lock_a_hooks" "$lock_b_hooks" "$lock_c_hooks"

    # A holds the kernel lock at the first critical-section boundary. B cannot
    # enter while A is alive, but automatically acquires after A is killed.
    LAUNCH_HOOK_DIR="$lock_a_hooks" \
    LAUNCH_HOOK_BLOCK_POINTS=after-state-lock-acquisition \
    HANDLE_TASK_LAUNCH_TEST_HOOK="$hook_script" \
        "$skill_dir/scripts/launch-job.sh" \
        "$lock_dir/a.launch.log" "$runner" \
        "$lock_status" "$lock_dir/job.log" \
        sh -c 'printf "%s\n" started >>"$1"; while [ ! -e "$2" ]; do sleep 0.01; done' \
        sh "$lock_count" "$lock_release" &
    lock_a=$!
    wait_for_path "$lock_a_hooks/after-state-lock-acquisition.entered"
    test -f "$lock_path"
    lock_inode=$(stat -Lc '%d:%i' "$lock_path")

    if HANDLE_TASK_LAUNCH_LOCK_ATTEMPTS=2 \
       HANDLE_TASK_LAUNCH_LOCK_DELAY=0.01 \
           "$skill_dir/scripts/launch-job.sh" \
           "$lock_dir/timeout.launch.log" "$runner" \
           "$lock_status" "$lock_dir/job.log" true \
           2>"$lock_dir/timeout.err"; then
        echo "Expected bounded lock acquisition to fail while A holds it" >&2
        exit 1
    fi
    grep -q '^Unable to acquire launch-state lock after 2 attempts: ' \
        "$lock_dir/timeout.err"
    test "$(stat -Lc '%d:%i' "$lock_path")" = "$lock_inode"

    LAUNCH_HOOK_DIR="$lock_b_hooks" \
    LAUNCH_HOOK_BLOCK_POINTS=after-state-lock-acquisition \
    HANDLE_TASK_LAUNCH_TEST_HOOK="$hook_script" \
    HANDLE_TASK_LAUNCH_LOCK_ATTEMPTS=500 \
    HANDLE_TASK_LAUNCH_LOCK_DELAY=0.01 \
        "$skill_dir/scripts/launch-job.sh" \
        "$lock_dir/b.launch.log" "$runner" \
        "$lock_status" "$lock_dir/job.log" \
        sh -c 'printf "%s\n" started >>"$1"; while [ ! -e "$2" ]; do sleep 0.01; done' \
        sh "$lock_count" "$lock_release" &
    lock_b=$!
    sleep 0.05
    test ! -e "$lock_b_hooks/after-state-lock-acquisition.entered"
    kill -0 "$lock_b"

    kill -KILL "$lock_a"
    wait "$lock_a" 2>/dev/null || true
    wait_for_path "$lock_b_hooks/after-state-lock-acquisition.entered"
    test "$(stat -Lc '%d:%i' "$lock_path")" = "$lock_inode"

    # C also waits while B owns the same inode. Releasing B lets contenders
    # serialize through that inode; generation checks still permit one runner.
    LAUNCH_HOOK_DIR="$lock_c_hooks" \
    HANDLE_TASK_LAUNCH_TEST_HOOK="$hook_script" \
    HANDLE_TASK_LAUNCH_LOCK_ATTEMPTS=500 \
    HANDLE_TASK_LAUNCH_LOCK_DELAY=0.01 \
        "$skill_dir/scripts/launch-job.sh" \
        "$lock_dir/c.launch.log" "$runner" \
        "$lock_status" "$lock_dir/job.log" \
        sh -c 'printf "%s\n" duplicate >>"$1"' sh "$lock_count" &
    lock_c=$!
    sleep 0.05
    test ! -e "$lock_c_hooks/after-state-lock-acquisition.entered"
    kill -0 "$lock_c"

    touch "$lock_b_hooks/after-state-lock-acquisition.release"
    wait_for_path "$lock_c_hooks/after-state-lock-acquisition.entered"
    wait "$lock_b"
    wait "$lock_c"
    wait_for_path "$lock_count"
    lock_runner_identity=$(cat "${lock_status}.pid")
    assert_live_identity "$lock_runner_identity"
    test "$(wc -l <"$lock_count" | tr -d '[:space:]')" = 1
    test "$(stat -Lc '%d:%i' "$lock_path")" = "$lock_inode"

    touch "$lock_release"
    wait_for_status "$lock_status"
    test "$(cat "$lock_status")" = 0
    test -f "$lock_path"
    test "$(stat -Lc '%d:%i' "$lock_path")" = "$lock_inode"
}

"$skill_dir/scripts/launch-job.sh" \
    "$launch_log" \
    "$runner" \
    "$status_file" "$job_log" \
    printf '%s\n' "$payload"

attempt=0
while [ ! -f "$status_file" ] && [ "$attempt" -lt 100 ]; do
    sleep 0.01
    attempt=$((attempt + 1))
done

test "$(cat "$status_file")" = 0
test "$(cat "$job_log")" = "$payload"
test ! -e "$test_dir/injected"
test "$("$skill_dir/scripts/inspect-job.sh" "$status_file" "${status_file}.pid")" = 0
test -d "${status_file}.launch"

# The marker is status-specific and remains authoritative after completion.
# A repeated invocation must neither clear status nor replace the recorded
# runner identity.
original_runner_identity=$(cat "${status_file}.pid")
"$skill_dir/scripts/launch-job.sh" \
    "$launch_log" \
    "$runner" \
    "$status_file" "$job_log" \
    sh -c 'exit 99'
test "$(cat "$status_file")" = 0
test "$(cat "${status_file}.pid")" = "$original_runner_identity"

durable_status="$test_dir/durable.status"
durable_log="$test_dir/durable.log"
durable_launch_log="$test_dir/durable-launch.log"
durable_count="$test_dir/durable-count"
durable_release="$test_dir/durable-release"
"$skill_dir/scripts/launch-job.sh" \
    "$durable_launch_log" \
    "$runner" \
    "$durable_status" "$durable_log" \
    sh -c 'printf "%s\n" started >>"$1"; while [ ! -e "$2" ]; do sleep 0.01; done' \
    sh "$durable_count" "$durable_release"

attempt=0
while [ ! -s "$durable_count" ] && [ "$attempt" -lt 100 ]; do
    sleep 0.01
    attempt=$((attempt + 1))
done
test -s "$durable_count"
durable_identity=$(cat "${durable_status}.pid")
assert_live_identity "$durable_identity"
durable_pid=${durable_identity%%:*}
test -d "${durable_status}.launch"
test "$("$skill_dir/scripts/inspect-job.sh" "$durable_status" "${durable_status}.pid")" = running

"$skill_dir/scripts/launch-job.sh" \
    "$durable_launch_log" \
    "$runner" \
    "$durable_status" "$durable_log" \
    sh -c 'printf "%s\n" duplicate >>"$1"' sh "$durable_count"
test "$(wc -l <"$durable_count" | tr -d '[:space:]')" = 1
test "$(cat "${durable_status}.pid")" = "$durable_identity"
test ! -e "$durable_status"

: >"$durable_release"
attempt=0
while [ ! -f "$durable_status" ] && [ "$attempt" -lt 100 ]; do
    sleep 0.01
    attempt=$((attempt + 1))
done
test "$(cat "$durable_status")" = 0
durable_pid=

# Deterministically model PID reuse by publishing this live test shell's PID
# with a different start time. The unrelated process must not be accepted as
# the committed runner. Launch remains fail-closed (no duplicate command), and
# both its diagnostic and the inspector report that the original runner is
# gone. No real PID exhaustion or reuse is required.
identity_probe=$(process_identity "$$")
identity_probe_pid=${identity_probe%%:*}
identity_probe_start=${identity_probe#*:}
reused_identity="$identity_probe_pid:$((identity_probe_start + 1))"
reused_dir="$test_dir/reused-runner-pid"
reused_status="$reused_dir/status"
reused_count="$reused_dir/count"
mkdir "$reused_dir"
printf '%s\n' "$reused_identity" >"${reused_status}.pid"
"$skill_dir/scripts/launch-job.sh" \
    "$reused_dir/retry.log" "$runner" \
    "$reused_status" "$reused_dir/job.log" \
    sh -c 'printf "%s\n" duplicate >>"$1"' sh "$reused_count" \
    2>"$reused_dir/retry.err"
test ! -e "$reused_count"
grep -q '^Committed runner identity is no longer live$' "$reused_dir/retry.err"
test "$("$skill_dir/scripts/inspect-job.sh" \
    "$reused_status" "${reused_status}.pid")" = runner-gone

# A legacy or corrupt bare PID is not a complete identity and is likewise
# fail-closed and reported gone rather than parsed as an authoritative runner.
bare_pid_dir="$test_dir/bare-runner-pid"
bare_pid_status="$bare_pid_dir/status"
bare_pid_count="$bare_pid_dir/count"
mkdir "$bare_pid_dir"
printf '%s\n' "$identity_probe_pid" >"${bare_pid_status}.pid"
"$skill_dir/scripts/launch-job.sh" \
    "$bare_pid_dir/retry.log" "$runner" \
    "$bare_pid_status" "$bare_pid_dir/job.log" \
    sh -c 'printf "%s\n" duplicate >>"$1"' sh "$bare_pid_count" \
    2>"$bare_pid_dir/retry.err"
test ! -e "$bare_pid_count"
grep -q '^Committed runner identity is no longer live$' \
    "$bare_pid_dir/retry.err"
test "$("$skill_dir/scripts/inspect-job.sh" \
    "$bare_pid_status" "${bare_pid_status}.pid")" = runner-gone

# The same PID with its matching start time remains authoritative and running.
matching_dir="$test_dir/matching-runner-identity"
matching_status="$matching_dir/status"
matching_count="$matching_dir/count"
mkdir "$matching_dir"
printf '%s\n' "$identity_probe" >"${matching_status}.pid"
"$skill_dir/scripts/launch-job.sh" \
    "$matching_dir/retry.log" "$runner" \
    "$matching_status" "$matching_dir/job.log" \
    sh -c 'printf "%s\n" duplicate >>"$1"' sh "$matching_count"
test ! -e "$matching_count"
test "$("$skill_dir/scripts/inspect-job.sh" \
    "$matching_status" "${matching_status}.pid")" = running

# Interruption before a child exists must leave a recoverable claim. These
# cover the empty marker, published owner, and final pre-fork boundaries.
test_pre_fork_recovery interrupted-after-mkdir after-claim-mkdir
test_pre_fork_recovery interrupted-after-owner after-owner-publication
test_pre_fork_recovery interrupted-before-fork before-fork

# Repeat forced kernel-lock contention and interruption with three contenders.
lock_iteration=1
while [ "$lock_iteration" -le 10 ]; do
    test_kernel_lock_interruption "$lock_iteration"
    lock_iteration=$((lock_iteration + 1))
done

# An ordinary failure while our generation is still uncommitted removes the
# claim immediately; it does not require a later stale-owner timeout.
ordinary_dir="$test_dir/ordinary-pre-fork-failure"
ordinary_status="$ordinary_dir/status"
mkdir "$ordinary_dir"
if LAUNCH_HOOK_DIR="$ordinary_dir" \
   LAUNCH_HOOK_FAIL_POINTS=after-owner-publication \
   HANDLE_TASK_LAUNCH_TEST_HOOK="$hook_script" \
       "$skill_dir/scripts/launch-job.sh" \
       "$ordinary_dir/launch.log" "$runner" \
       "$ordinary_status" "$ordinary_dir/job.log" true; then
    echo "Expected the injected pre-fork failure" >&2
    exit 1
fi
test ! -e "${ordinary_status}.launch"
test ! -e "${ordinary_status}.pid"

# Fork the child, hold it before identity publication, and interrupt the parent
# at its first post-fork hook. Keep the old child delayed beyond observation so
# recovery authorizes a replacement; when released, the old child sees the
# changed generation and exits without becoming a second runner.
fork_dir="$test_dir/interrupted-after-fork"
fork_status="$fork_dir/status"
fork_count="$fork_dir/count"
mkdir "$fork_dir"
LAUNCH_HOOK_DIR="$fork_dir" \
LAUNCH_HOOK_BLOCK_POINTS=after-fork,child-before-pid-publication \
HANDLE_TASK_LAUNCH_TEST_HOOK="$hook_script" \
HANDLE_TASK_LAUNCH_PUBLISH_ATTEMPTS=1000 \
    "$skill_dir/scripts/launch-job.sh" \
    "$fork_dir/launch.log" "$runner" "$fork_status" "$fork_dir/job.log" \
    sh -c 'printf "%s\n" started >>"$1"' sh "$fork_count" &
fork_launcher=$!
wait_for_path "$fork_dir/after-fork.entered"
wait_for_path "$fork_dir/child-before-pid-publication.entered"
kill -KILL "$fork_launcher"
wait "$fork_launcher" 2>/dev/null || true
HANDLE_TASK_LAUNCH_OBSERVE_ATTEMPTS=2 \
HANDLE_TASK_LAUNCH_OBSERVE_DELAY=0.01 \
    "$skill_dir/scripts/launch-job.sh" \
    "$fork_dir/retry.log" "$runner" "$fork_status" "$fork_dir/job.log" \
    sh -c 'printf "%s\n" duplicate >>"$1"' sh "$fork_count" &
fork_retry=$!
wait "$fork_retry"
wait_for_status "$fork_status"
touch "$fork_dir/child-before-pid-publication.release"
sleep 0.05
assert_single_success "$fork_status" "$fork_count"

# A retry that finds the initial launcher alive must fail closed after bounded
# observation, not acknowledge the uncommitted launch or reclaim its child.
# After that observation, kill the original launcher before publication. A
# later controller retry lets the delayed child commit during dead-owner
# observation, without starting a replacement runner.
before_pid_dir="$test_dir/before-child-pid"
before_pid_status="$before_pid_dir/status"
before_pid_count="$before_pid_dir/count"
mkdir "$before_pid_dir"
LAUNCH_HOOK_DIR="$before_pid_dir" \
LAUNCH_HOOK_BLOCK_POINTS=child-before-pid-publication \
HANDLE_TASK_LAUNCH_TEST_HOOK="$hook_script" \
HANDLE_TASK_LAUNCH_PUBLISH_ATTEMPTS=1000 \
    "$skill_dir/scripts/launch-job.sh" \
    "$before_pid_dir/launch.log" "$runner" \
    "$before_pid_status" "$before_pid_dir/job.log" \
    sh -c 'printf "%s\n" started >>"$1"' sh "$before_pid_count" &
before_pid_launcher=$!
wait_for_path "$before_pid_dir/child-before-pid-publication.entered"
if HANDLE_TASK_LAUNCH_OBSERVE_ATTEMPTS=2 \
   HANDLE_TASK_LAUNCH_OBSERVE_DELAY=0.01 \
       "$skill_dir/scripts/launch-job.sh" \
       "$before_pid_dir/live-owner-retry.log" "$runner" \
       "$before_pid_status" "$before_pid_dir/job.log" \
       sh -c 'printf "%s\n" duplicate >>"$1"' sh "$before_pid_count"; then
    echo "Expected live uncommitted owner observation to fail closed" >&2
    exit 1
fi
test ! -e "$before_pid_count"
test ! -e "${before_pid_status}.pid"
kill -0 "$before_pid_launcher"
kill -KILL "$before_pid_launcher"
wait "$before_pid_launcher" 2>/dev/null || true
HANDLE_TASK_LAUNCH_OBSERVE_ATTEMPTS=100 \
HANDLE_TASK_LAUNCH_OBSERVE_DELAY=0.01 \
    "$skill_dir/scripts/launch-job.sh" \
    "$before_pid_dir/dead-owner-retry.log" "$runner" \
    "$before_pid_status" "$before_pid_dir/job.log" \
    sh -c 'printf "%s\n" duplicate >>"$1"' sh "$before_pid_count" &
before_pid_retry=$!
sleep 0.05
touch "$before_pid_dir/child-before-pid-publication.release"
wait "$before_pid_retry"
assert_single_success "$before_pid_status" "$before_pid_count"

# The initial launcher also fails closed when its own bounded publication wait
# expires while the child is alive. The preserved generation allows that slow
# child to publish during a later retry's dead-owner observation.
slow_dir="$test_dir/slow-publication"
slow_status="$slow_dir/status"
slow_count="$slow_dir/count"
mkdir "$slow_dir"
if LAUNCH_HOOK_DIR="$slow_dir" \
   LAUNCH_HOOK_BLOCK_POINTS=child-before-pid-publication \
   HANDLE_TASK_LAUNCH_TEST_HOOK="$hook_script" \
   HANDLE_TASK_LAUNCH_PUBLISH_ATTEMPTS=2 \
   HANDLE_TASK_LAUNCH_PUBLISH_DELAY=0.01 \
       "$skill_dir/scripts/launch-job.sh" \
       "$slow_dir/launch.log" "$runner" "$slow_status" "$slow_dir/job.log" \
       sh -c 'printf "%s\n" started >>"$1"' sh "$slow_count"; then
    echo "Expected unpublished live child timeout to fail closed" >&2
    exit 1
fi
test ! -e "${slow_status}.pid"
test ! -e "$slow_count"
HANDLE_TASK_LAUNCH_OBSERVE_ATTEMPTS=100 \
HANDLE_TASK_LAUNCH_OBSERVE_DELAY=0.01 \
    "$skill_dir/scripts/launch-job.sh" \
    "$slow_dir/retry.log" "$runner" "$slow_status" "$slow_dir/job.log" \
    sh -c 'printf "%s\n" duplicate >>"$1"' sh "$slow_count" &
slow_retry=$!
sleep 0.05
touch "$slow_dir/child-before-pid-publication.release"
wait "$slow_retry"
assert_single_success "$slow_status" "$slow_count"

# Publication may also be slow but finish inside the initial launcher's bound;
# in that case the initial invocation returns success with the PID committed.
slow_success_dir="$test_dir/slow-publication-success"
slow_success_status="$slow_success_dir/status"
slow_success_count="$slow_success_dir/count"
mkdir "$slow_success_dir"
LAUNCH_HOOK_DIR="$slow_success_dir" \
LAUNCH_HOOK_BLOCK_POINTS=child-before-pid-publication \
HANDLE_TASK_LAUNCH_TEST_HOOK="$hook_script" \
HANDLE_TASK_LAUNCH_PUBLISH_ATTEMPTS=100 \
HANDLE_TASK_LAUNCH_PUBLISH_DELAY=0.01 \
    "$skill_dir/scripts/launch-job.sh" \
    "$slow_success_dir/launch.log" "$runner" \
    "$slow_success_status" "$slow_success_dir/job.log" \
    sh -c 'printf "%s\n" started >>"$1"' sh "$slow_success_count" &
slow_success_launcher=$!
wait_for_path "$slow_success_dir/child-before-pid-publication.entered"
sleep 0.05
touch "$slow_success_dir/child-before-pid-publication.release"
wait "$slow_success_launcher"
test -s "${slow_success_status}.pid"
assert_single_success "$slow_success_status" "$slow_success_count"

# A child that exits before identity publication makes the launcher fail and
# removes its uncommitted claim, so a subsequent invocation starts exactly once.
child_death_dir="$test_dir/child-death"
child_death_status="$child_death_dir/status"
child_death_count="$child_death_dir/count"
mkdir "$child_death_dir"
if LAUNCH_HOOK_DIR="$child_death_dir" \
   LAUNCH_HOOK_FAIL_POINTS=child-before-pid-publication \
   HANDLE_TASK_LAUNCH_TEST_HOOK="$hook_script" \
   HANDLE_TASK_LAUNCH_PUBLISH_DELAY=0.01 \
       "$skill_dir/scripts/launch-job.sh" \
       "$child_death_dir/launch.log" "$runner" \
       "$child_death_status" "$child_death_dir/job.log" \
       sh -c 'printf "%s\n" started >>"$1"' sh "$child_death_count"; then
    echo "Expected child death before identity publication to fail" >&2
    exit 1
fi
test ! -e "${child_death_status}.launch"
test ! -e "${child_death_status}.pid"
"$skill_dir/scripts/launch-job.sh" \
    "$child_death_dir/retry.log" "$runner" \
    "$child_death_status" "$child_death_dir/job.log" \
    sh -c 'printf "%s\n" started >>"$1"' sh "$child_death_count"
assert_single_success "$child_death_status" "$child_death_count"

# Once the child has atomically published its identity, retries must treat it as
# committed even while it is paused before execing the runner.
after_pid_dir="$test_dir/after-child-pid"
after_pid_status="$after_pid_dir/status"
after_pid_count="$after_pid_dir/count"
mkdir "$after_pid_dir"
LAUNCH_HOOK_DIR="$after_pid_dir" \
LAUNCH_HOOK_BLOCK_POINTS=child-after-pid-publication \
HANDLE_TASK_LAUNCH_TEST_HOOK="$hook_script" \
    "$skill_dir/scripts/launch-job.sh" \
    "$after_pid_dir/launch.log" "$runner" \
    "$after_pid_status" "$after_pid_dir/job.log" \
    sh -c 'printf "%s\n" started >>"$1"' sh "$after_pid_count" &
after_pid_launcher=$!
wait_for_path "$after_pid_dir/child-after-pid-publication.entered"
test -s "${after_pid_status}.pid"
# The durable child has released and closed its lock FD before runner exec.
flock -n "${after_pid_status}.launch-lock" true
"$skill_dir/scripts/launch-job.sh" \
    "$after_pid_dir/retry.log" "$runner" \
    "$after_pid_status" "$after_pid_dir/job.log" \
    sh -c 'printf "%s\n" duplicate >>"$1"' sh "$after_pid_count" &
after_pid_retry=$!
sleep 0.05
touch "$after_pid_dir/child-after-pid-publication.release"
wait "$after_pid_launcher"
wait "$after_pid_retry"
assert_single_success "$after_pid_status" "$after_pid_count"

# A malformed, ownerless marker is a poisoned stale claim and must not suppress
# eventual progress.
poison_dir="$test_dir/poisoned-claim"
poison_status="$poison_dir/status"
poison_count="$poison_dir/count"
mkdir -p "${poison_status}.launch"
printf '%s\n' invalid >"${poison_status}.launch/owner"
HANDLE_TASK_LAUNCH_OBSERVE_ATTEMPTS=2 \
HANDLE_TASK_LAUNCH_OBSERVE_DELAY=0.01 \
    "$skill_dir/scripts/launch-job.sh" \
    "$poison_dir/launch.log" "$runner" "$poison_status" "$poison_dir/job.log" \
    sh -c 'printf "%s\n" started >>"$1"' sh "$poison_count"
assert_single_success "$poison_status" "$poison_count"

# A genuine nonzero job result is completed status, not a stale launch. A
# retry preserves that result and does not run a second command.
failure_dir="$test_dir/genuine-failure"
failure_status="$failure_dir/status"
failure_count="$failure_dir/count"
mkdir "$failure_dir"
"$skill_dir/scripts/launch-job.sh" \
    "$failure_dir/launch.log" "$runner" "$failure_status" "$failure_dir/job.log" \
    sh -c 'printf "%s\n" failed >>"$1"; exit 23' sh "$failure_count"
wait_for_status "$failure_status"
test "$(cat "$failure_status")" = 23
"$skill_dir/scripts/launch-job.sh" \
    "$failure_dir/retry.log" "$runner" "$failure_status" "$failure_dir/job.log" \
    sh -c 'printf "%s\n" duplicate >>"$1"' sh "$failure_count"
test "$(cat "$failure_status")" = 23
test "$(wc -l <"$failure_count" | tr -d '[:space:]')" = 1

missing_status="$test_dir/missing.status"
"$skill_dir/scripts/launch-job.sh" \
    "$test_dir/missing.launch.log" \
    "$test_dir/does-not-exist" \
    "$missing_status" "$test_dir/missing.job.log"
attempt=0
state=running
while [ "$state" = running ] && [ "$attempt" -lt 100 ]; do
    state=$("$skill_dir/scripts/inspect-job.sh" "$missing_status" "${missing_status}.pid")
    sleep 0.01
    attempt=$((attempt + 1))
done
test "$state" = runner-gone
test -d "${missing_status}.launch"
test -s "${missing_status}.pid"

signal_status="$test_dir/signal.status"
signal_log="$test_dir/signal.log"
"$skill_dir/scripts/run-job.sh" "$signal_status" "$signal_log" \
    sh -c 'kill -TERM $$' || :
test "$(cat "$signal_status")" = 143

hup_status="$test_dir/hup.status"
hup_log="$test_dir/hup.log"
"$skill_dir/scripts/run-job.sh" "$hup_status" "$hup_log" \
    sh -c 'kill -HUP "$PPID"; printf survived' &
hup_runner=$!
wait "$hup_runner"
test "$(cat "$hup_status")" = 0
test "$(cat "$hup_log")" = survived
