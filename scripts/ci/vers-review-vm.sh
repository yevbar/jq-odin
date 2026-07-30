#!/bin/sh
set -eu

review_dir=/tmp/jq-review

finish() {
    status=$?
    trap - EXIT HUP INT TERM
    printf '%s\n' "$status" >"$review_dir/exit-code"
    exit "$status"
}
trap finish EXIT HUP INT TERM

sync_clock() {
    before=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if command -v chronyd >/dev/null 2>&1; then
        chronyd -q -t 20 "pool pool.ntp.org iburst" \
            >"$review_dir/time-sync.log" 2>&1
    elif command -v ntpd >/dev/null 2>&1; then
        ntpd -gq >"$review_dir/time-sync.log" 2>&1
    else
        server_date=$(
            curl -fsSI --max-time 15 https://github.com |
                awk 'BEGIN { IGNORECASE=1 } /^date:/ {
                    sub(/^[^:]*:[[:space:]]*/, "")
                    sub(/\r$/, "")
                    value=$0
                } END { print value }'
        )
        if [ -z "$server_date" ]; then
            echo "Unable to obtain current time" >&2
            exit 1
        fi
        date -u -s "$server_date" >"$review_dir/time-sync.log"
    fi

    echo "Clock synchronized: $before -> $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

for file in manifest.txt files.tsv change.diff PROMPT.md result.schema.json; do
    test -f "$review_dir/$file"
done

sync_clock

# Review VMs do not need source-control or orchestration credentials. Vers
# credentials are never sent to the VM; remove any organization-injected
# GitHub credentials before the reviewer starts.
unset GITHUB_API_KEY GH_TOKEN GITHUB_TOKEN VERS_API_KEY

# The approved snapshot may contain a stale working checkout for author tasks.
# Remove that exact disposable-VM path so the reviewer has only the packet.
if [ -d /workspace/jq-experiment ]; then
    rm -rf /workspace/jq-experiment
fi

{
    cat "$review_dir/PROMPT.md"
    printf '\n\n--- BEGIN REVIEW PACKET ---\n\n'
    printf '### manifest.txt\n\n```text\n'
    cat "$review_dir/manifest.txt"
    printf '```\n\n### files.tsv\n\n```text\n'
    cat "$review_dir/files.tsv"
    printf '```\n\n### change.diff\n\n```diff\n'
    cat "$review_dir/change.diff"
    printf '```\n\n--- END REVIEW PACKET ---\n'
} >"$review_dir/request.md"

codex --version
codex exec \
    --model gpt-5.6-sol \
    --config 'model_reasoning_effort="high"' \
    --sandbox read-only \
    --skip-git-repo-check \
    --color never \
    --cd "$review_dir" \
    --output-schema "$review_dir/result.schema.json" \
    --output-last-message "$review_dir/result.json" \
    - <"$review_dir/request.md"

jq -e '
    (
      .recommendation == "merge_as_is" and
      .quality_score >= 4 and
      (.confidence == "medium" or .confidence == "high") and
      (.findings | length == 0)
    ) or (
      .recommendation == "task_agent" and
      (.findings | length > 0)
    )
' "$review_dir/result.json" >/dev/null
