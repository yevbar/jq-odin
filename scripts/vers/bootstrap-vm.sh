#!/bin/sh
set -eu

if [ "$(id -u)" -eq 0 ] && command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates clang curl gh git make
fi

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root_dir"

git submodule update --init --recursive
make bootstrap
make validate
