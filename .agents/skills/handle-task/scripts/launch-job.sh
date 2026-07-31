#!/bin/sh
set -eu

launch_log=${1:?launch log is required}
runner=${2:?job runner is required}
status_file=${3:?status file is required}
job_log=${4:?job log is required}
shift 4

rm -f "$status_file"
rm -f "${status_file}.pid"
nohup sh "$runner" "$status_file" "$job_log" "$@" \
    </dev/null >"$launch_log" 2>&1 &
printf '%s\n' "$!" >"${status_file}.pid"
