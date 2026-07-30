#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
source_repo="$root/upstream/jq"
onig_repo="$source_repo/vendor/oniguruma"
expected_jq=4467af7068b1bcd7f882defff6e7ea674c5357f4
expected_onig=4ef89209a239c1aea328cf13c05a2807e5c146d1

for dependency in git tar autoreconf make mktemp; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        echo "Required command not found: $dependency" >&2
        exit 1
    fi
done

actual_jq=$(git -C "$source_repo" rev-parse HEAD)
actual_onig=$(git -C "$onig_repo" rev-parse HEAD)
if [ "$actual_jq" != "$expected_jq" ]; then
    echo "jq source is $actual_jq; expected $expected_jq" >&2
    exit 1
fi
if [ "$actual_onig" != "$expected_onig" ]; then
    echo "Oniguruma source is $actual_onig; expected $expected_onig" >&2
    exit 1
fi
mkdir -p "$root/.tools"
build_root=$(mktemp -d "$root/.tools/jq-oracle-1.8.1.XXXXXX")
work_dir="$build_root/source"
prefix="$build_root/install"
oracle="$prefix/bin/jq"
complete=false
trap 'if [ "$complete" != true ]; then echo "Incomplete oracle build preserved at $build_root" >&2; fi' 0

mkdir -p "$work_dir/vendor/oniguruma" "$prefix"
git -C "$source_repo" archive "$expected_jq" | tar -x -C "$work_dir"
git -C "$onig_repo" archive "$expected_onig" |
    tar -x -C "$work_dir/vendor/oniguruma"

# jq derives both its package version and JQ_VERSION from Git. Give the
# disposable source copy the exact release tag instead of modifying the
# immutable reference checkout or accepting an unversioned binary.
git -C "$work_dir" init -q
git -C "$work_dir" config user.name jq-oracle-builder
git -C "$work_dir" config user.email jq-oracle-builder@invalid
git -C "$work_dir" add -A
git -C "$work_dir" commit -qm "jq 1.8.1 oracle source"
git -C "$work_dir" tag jq-1.8.1

if command -v glibtoolize >/dev/null 2>&1 &&
    ! command -v libtoolize >/dev/null 2>&1; then
    export LIBTOOLIZE=glibtoolize
fi

(
    cd "$work_dir"
    autoreconf -fi

    # autoreconf refreshes some tracked bootstrap files. The release version
    # script asks Git whether tracked files are dirty, so hide those disposable
    # build-copy changes from the index before jq generates src/version.h.
    # Untracked build products do not affect `git describe --dirty`.
    git ls-files -z |
        git update-index --assume-unchanged -z --stdin

    ./configure \
        --prefix="$prefix" \
        --disable-maintainer-mode \
        --with-oniguruma=builtin
    make -j 2
    make install
) >&2

version=$("$oracle" --version)
if [ "$version" != jq-1.8.1 ]; then
    echo "Built oracle reports $version; expected jq-1.8.1" >&2
    exit 1
fi

complete=true
printf '%s\n' "$oracle"
