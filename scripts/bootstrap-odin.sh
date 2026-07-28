#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=$(sed -n '1p' "$root_dir/.odin-version")
install_dir="$root_dir/.tools/odin-$version"

if [ -x "$install_dir/odin" ]; then
    "$install_dir/odin" version
    exit 0
fi

os=$(uname -s)
arch=$(uname -m)

case "$os/$arch" in
    Darwin/arm64)
        platform=macos-arm64
        expected_sha256=0f50c8bc8ce1106786f0cc7dc22dae32aab7c40d525ba0f8629f8c0952deb20a
        ;;
    Darwin/x86_64)
        platform=macos-amd64
        expected_sha256=48c43397e01fed5fe937dc0fa6031dae9a7d145e2ba52cb25cede6ba771b3ac6
        ;;
    Linux/aarch64|Linux/arm64)
        platform=linux-arm64
        expected_sha256=48e93e5534ac4bea52e9cb986830d414bfe8b0ce3ff08416d6131ba0b18d0435
        ;;
    Linux/x86_64)
        platform=linux-amd64
        expected_sha256=cd7ec2cd1ab2840a0b7ebc18e5cb41c671bce87b12f056fddbef3f080b4dde7d
        ;;
    *)
        echo "Unsupported host for the pinned Odin binary: $os/$arch" >&2
        exit 1
        ;;
esac

archive_name="odin-$platform-$version.tar.gz"
url="https://github.com/odin-lang/Odin/releases/download/$version/$archive_name"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/jq-odin-bootstrap.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

echo "Downloading $url"
curl -fL --retry 3 -o "$tmp_dir/$archive_name" "$url"

if command -v shasum >/dev/null 2>&1; then
    actual_sha256=$(shasum -a 256 "$tmp_dir/$archive_name" | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then
    actual_sha256=$(sha256sum "$tmp_dir/$archive_name" | awk '{print $1}')
else
    echo "Neither shasum nor sha256sum is available" >&2
    exit 1
fi
if [ "$actual_sha256" != "$expected_sha256" ]; then
    echo "Odin archive checksum mismatch" >&2
    echo "expected: $expected_sha256" >&2
    echo "actual:   $actual_sha256" >&2
    exit 1
fi

mkdir -p "$install_dir"
tar -xzf "$tmp_dir/$archive_name" -C "$install_dir" --strip-components=1

"$install_dir/odin" version
echo "Installed the repository-local compiler at $install_dir"
