#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
expected_jq=4467af7068b1bcd7f882defff6e7ea674c5357f4

actual_jq=$(git -C "$root_dir/upstream/jq" rev-parse HEAD)
if [ "$actual_jq" != "$expected_jq" ]; then
    echo "jq upstream is $actual_jq; expected $expected_jq" >&2
    exit 1
fi

if [ -n "$(git -C "$root_dir/upstream/jq" status --short)" ]; then
    echo "upstream/jq is dirty; the reference checkout must remain immutable" >&2
    exit 1
fi

for package_name in diagnostic value json syntax program compiler eval; do
    marker="$root_dir/src/$package_name/package.odin"
    if [ ! -f "$marker" ]; then
        echo "missing package marker: $marker" >&2
        exit 1
    fi
done

for script in "$root_dir"/scripts/*.sh "$root_dir"/scripts/vers/*.sh; do
    sh -n "$script"
done

echo "Repository layout is consistent."

