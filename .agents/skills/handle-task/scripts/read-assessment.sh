#!/bin/sh
set -eu

usage() {
    cat <<'EOF'
Usage: read-assessment.sh --pr NUMBER [--repo OWNER/REPO]
EOF
}

pr_number=
repository=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --pr)
            pr_number=${2:?missing value for --pr}
            shift 2
            ;;
        --repo)
            repository=${2:?missing value for --repo}
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$pr_number" in
    *[!0-9]*|'')
        echo "PR number must be a positive integer" >&2
        exit 2
        ;;
esac

for dependency in gh jq unzip; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        echo "Required command not found: $dependency" >&2
        exit 1
    fi
done

if [ -z "$repository" ]; then
    repository=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi

head_sha=$(
    gh pr view "$pr_number" \
        --repo "$repository" \
        --json headRefOid \
        --jq .headRefOid
)
artifact_name="adversarial-assessment-$pr_number-$head_sha"

artifact_id=$(
    gh api "repos/$repository/actions/artifacts?name=$artifact_name&per_page=100" \
        --jq '
            .artifacts
            | map(select(.expired == false))
            | sort_by(.created_at)
            | last
            | .id
        '
)

if [ -z "$artifact_id" ] || [ "$artifact_id" = null ]; then
    echo "No current-head adversarial assessment: $artifact_name" >&2
    exit 1
fi

archive=$(mktemp "${TMPDIR:-/tmp}/jq-assessment.XXXXXX.zip")
trap 'rm -f "$archive"' EXIT HUP INT TERM

gh api "repos/$repository/actions/artifacts/$artifact_id/zip" >"$archive"
unzip -p "$archive" result.json
