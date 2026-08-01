#!/bin/sh
set -eu

status_file=${1:?status file is required}
runner_identity_file=${2:?runner identity file is required}

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

read_identity() {
    identity_file=$1
    awk '
        NR == 1 && /^[0-9][0-9]*:[0-9][0-9]*$/ { identity = $0; next }
        { invalid = 1 }
        END { if (NR == 1 && !invalid) print identity }
    ' "$identity_file" 2>/dev/null || true
}

identity_is_live() {
    expected_identity=$1
    identity_pid=${expected_identity%%:*}
    [ "$(process_identity "$identity_pid")" = "$expected_identity" ]
}

if [ -s "$status_file" ]; then
    status=$(sed -n '/^[0-9][0-9]*$/p' "$status_file" | sed -n '$p')
    if [ -n "$status" ]; then
        printf '%s\n' "$status"
        exit 0
    fi
fi

if [ ! -s "$runner_identity_file" ]; then
    printf '%s\n' starting
    exit 0
fi

runner_identity=$(read_identity "$runner_identity_file")
if [ -z "$runner_identity" ]; then
    printf '%s\n' runner-gone
    exit 0
fi

if identity_is_live "$runner_identity"; then
    printf '%s\n' running
else
    printf '%s\n' runner-gone
fi
