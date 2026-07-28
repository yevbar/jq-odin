#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=$(sed -n '1p' "$root_dir/.odin-version")
local_odin="$root_dir/.tools/odin-$version/odin"
failed=0

if [ -x "$local_odin" ]; then
    odin_bin=$local_odin
elif command -v odin >/dev/null 2>&1; then
    odin_bin=$(command -v odin)
else
    echo "FAIL: Odin not found; run 'make bootstrap'" >&2
    failed=1
    odin_bin=
fi

if command -v git >/dev/null 2>&1; then
    echo "OK:   $(git --version)"
else
    echo "FAIL: git not found" >&2
    failed=1
fi

if command -v clang >/dev/null 2>&1; then
    echo "OK:   $(clang --version | sed -n '1p')"
else
    echo "FAIL: clang not found (install the platform C/linker toolchain)" >&2
    failed=1
fi

if [ -n "$odin_bin" ]; then
    reported_version=$("$odin_bin" version)
    echo "OK:   $reported_version ($odin_bin)"
    case "$reported_version" in
        *"$version"*) ;;
        *)
            echo "FAIL: expected Odin $version" >&2
            failed=1
            ;;
    esac
fi

expected_jq=4467af7068b1bcd7f882defff6e7ea674c5357f4
if [ -d "$root_dir/upstream/jq" ]; then
    actual_jq=$(git -C "$root_dir/upstream/jq" rev-parse HEAD)
    if [ "$actual_jq" = "$expected_jq" ]; then
        echo "OK:   jq upstream $actual_jq"
    else
        echo "FAIL: jq upstream is $actual_jq; expected $expected_jq" >&2
        failed=1
    fi
else
    echo "FAIL: upstream/jq missing; initialize Git submodules" >&2
    failed=1
fi

if [ "$failed" -ne 0 ]; then
    exit 1
fi

echo "Environment is ready for the next setup pass."
