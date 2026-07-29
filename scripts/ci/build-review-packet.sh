#!/bin/sh
set -eu

source_repo=${1:?source repository is required}
base_sha=${2:?base SHA is required}
head_sha=${3:?head SHA is required}
output_dir=${4:?output directory is required}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
trusted_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

for revision in "$base_sha" "$head_sha"; do
    git -C "$source_repo" cat-file -e "$revision^{commit}"
done

merge_base=$(git -C "$source_repo" merge-base "$base_sha" "$head_sha")

if [ -e "$output_dir" ]; then
    echo "Review packet output already exists: $output_dir" >&2
    exit 1
fi

mkdir -p "$output_dir"

{
    printf 'review_model=diff-centric\n'
    printf 'base_sha=%s\n' "$base_sha"
    printf 'head_sha=%s\n' "$head_sha"
    printf 'merge_base_sha=%s\n' "$merge_base"
    printf 'comparison=%s...%s\n' "$base_sha" "$head_sha"
} >"$output_dir/manifest.txt"

git -C "$source_repo" diff \
    --name-status \
    --find-renames \
    --find-copies \
    --no-ext-diff \
    --no-textconv \
    "$base_sha...$head_sha" \
    >"$output_dir/files.tsv"

git -C "$source_repo" diff \
    --full-index \
    --binary \
    --find-renames \
    --find-copies \
    --no-color \
    --no-ext-diff \
    --no-textconv \
    --src-prefix=a/ \
    --dst-prefix=b/ \
    --submodule=short \
    --unified=80 \
    "$base_sha...$head_sha" \
    >"$output_dir/change.diff"

cp "$trusted_root/.github/review/PROMPT.md" "$output_dir/PROMPT.md"
cp "$trusted_root/.github/review/result.schema.json" \
    "$output_dir/result.schema.json"

printf 'Review packet: %s -> %s (%s)\n' \
    "$merge_base" "$head_sha" "$output_dir"
