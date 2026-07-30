#!/bin/sh
set -eu

status_file=${1:?status file is required}
pid_file=${2:?pid file is required}

if [ -s "$status_file" ]; then
    status=$(sed -n '/^[0-9][0-9]*$/p' "$status_file" | sed -n '$p')
    if [ -n "$status" ]; then
        printf '%s\n' "$status"
        exit 0
    fi
fi

if [ ! -s "$pid_file" ]; then
    printf '%s\n' starting
    exit 0
fi

pid=$(sed -n '/^[0-9][0-9]*$/p' "$pid_file" | sed -n '$p')
if [ -z "$pid" ]; then
    printf '%s\n' runner-gone
    exit 0
fi

if kill -0 "$pid" 2>/dev/null; then
    printf '%s\n' running
else
    printf '%s\n' runner-gone
fi
