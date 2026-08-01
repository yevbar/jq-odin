#!/bin/sh
set -eu

if [ "$(id -u)" -eq 0 ] && command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates clang curl gh git make util-linux
fi

if ! command -v flock >/dev/null 2>&1; then
    echo "Required Linux command not found after bootstrap: flock (util-linux)" >&2
    exit 1
fi

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root_dir"

git submodule update --init --recursive
make bootstrap
make validate
