#!/bin/sh
set -eu

skill_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/handle-task-launch-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

payload="literal'; touch $test_dir/injected; #"
status_file="$test_dir/status"
job_log="$test_dir/job.log"
launch_log="$test_dir/launch.log"

"$skill_dir/scripts/launch-job.sh" \
    "$launch_log" \
    "$skill_dir/scripts/run-job.sh" \
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
