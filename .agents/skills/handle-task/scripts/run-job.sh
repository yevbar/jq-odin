#!/bin/sh
set -u

status_file=${1:?status file is required}
log_file=${2:?log file is required}
shift 2

rm -f "$status_file"
status=125

record_status() {
    status_temp="${status_file}.tmp.$$"
    printf '%s\n' "$status" >"$status_temp"
    mv "$status_temp" "$status_file"
}

trap '' HUP
trap 'status=130; exit "$status"' INT
trap 'status=143; exit "$status"' TERM
trap 'record_status' EXIT

set +e
"$@" >"$log_file" 2>&1
status=$?
exit "$status"
