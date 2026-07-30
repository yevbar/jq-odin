#!/bin/sh
set -eu

repo_dir=${1:?repository directory is required}
prompt_file=${2:?prompt file is required}

export GH_TOKEN=${GH_TOKEN:-$GITHUB_API_KEY}
cd "$repo_dir"
exec codex-worker exec \
    --dangerously-bypass-approvals-and-sandbox \
    --color never \
    -C "$repo_dir" \
    - <"$prompt_file"
