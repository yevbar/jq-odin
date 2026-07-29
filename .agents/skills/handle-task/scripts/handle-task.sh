#!/bin/sh
set -eu

default_commit=13b7c648-7849-4b9b-a788-16b4522edeb8
default_repo=https://github.com/hdresearch/jq-experiment.git
default_repo_dir=/workspace/jq-experiment

usage() {
    cat <<'EOF'
Usage:
  handle-task.sh --workstream ID --task SLUG --prompt-file FILE [options]
  handle-task.sh --workstream ID --task SLUG --prepare-only [options]

Options:
  --base BRANCH       Integration base (default: main)
  --commit KEY        Vers commit key
  --disk-size MIB     Minimum task disk size (default: 8192)
  --repo URL          GitHub repository URL
  --repo-dir PATH     Repository location inside the VM
  --prepare-only      Prepare the VM without starting Codex
EOF
}

workstream=
task_slug=
prompt_file=
base_branch=main
commit_key=${JQ_CODEX_VERS_COMMIT:-$default_commit}
disk_size_mib=8192
repo_url=$default_repo
repo_dir=$default_repo_dir
prepare_only=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --workstream)
            workstream=${2:?missing value for --workstream}
            shift 2
            ;;
        --task)
            task_slug=${2:?missing value for --task}
            shift 2
            ;;
        --prompt-file)
            prompt_file=${2:?missing value for --prompt-file}
            shift 2
            ;;
        --base)
            base_branch=${2:?missing value for --base}
            shift 2
            ;;
        --commit)
            commit_key=${2:?missing value for --commit}
            shift 2
            ;;
        --disk-size)
            disk_size_mib=${2:?missing value for --disk-size}
            shift 2
            ;;
        --repo)
            repo_url=${2:?missing value for --repo}
            shift 2
            ;;
        --repo-dir)
            repo_dir=${2:?missing value for --repo-dir}
            shift 2
            ;;
        --prepare-only)
            prepare_only=true
            shift
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

case "$workstream" in
    facts|compat|value|json|language|program|eval|specialty|cli|integration)
        ;;
    *)
        echo "Unknown workstream: $workstream" >&2
        exit 2
        ;;
esac

case "$task_slug" in
    *[!a-z0-9-]*|'')
        echo "Task slug must contain lowercase letters, digits, and hyphens" >&2
        exit 2
        ;;
esac

case "$disk_size_mib" in
    *[!0-9]*|'')
        echo "Disk size must be a positive integer in MiB" >&2
        exit 2
        ;;
esac
if [ "$disk_size_mib" -eq 0 ]; then
    echo "Disk size must be greater than zero" >&2
    exit 2
fi

if [ "$prepare_only" = false ]; then
    if [ -z "$prompt_file" ] || [ ! -f "$prompt_file" ]; then
        echo "--prompt-file must name an existing file" >&2
        exit 2
    fi
fi

for dependency in vers jq; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        echo "Required local command not found: $dependency" >&2
        exit 1
    fi
done

feature_branch="agent/$workstream/$task_slug"
alias_suffix=$(date +%s)
vm_alias="jq-$workstream-$task_slug-$alias_suffix"
skill_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
prepare_script="$skill_dir/scripts/prepare-vm.sh"

echo "Booting Vers commit $commit_key"
run_json=$(
    vers run-commit "$commit_key" \
        --vm-alias "$vm_alias" \
        --wait \
        --format json
)
vm_id=$(printf '%s\n' "$run_json" | jq -er .vm_id)

current_disk_kib=$(
    vers exec --ssh -t 60 "$vm_id" env HOME=/root sh -lc \
        "df -Pk / | awk 'NR == 2 { print \$2 }'"
)
current_disk_mib=$((current_disk_kib / 1024))
if [ "$current_disk_mib" -lt "$disk_size_mib" ]; then
    echo "Growing VM disk: ${current_disk_mib} MiB -> ${disk_size_mib} MiB"
    vers resize "$vm_id" --size "$disk_size_mib"
fi

echo "Preparing VM $vm_id"
if ! vers exec --ssh -i -t 1800 "$vm_id" env HOME=/root sh -s -- \
    "$repo_url" "$base_branch" "$feature_branch" "$repo_dir" \
    <"$prepare_script"; then
    echo "VM preparation failed; preserved for diagnosis: $vm_id" >&2
    exit 1
fi

printf '%s\n' \
    "VM_ID=$vm_id" \
    "VM_ALIAS=$vm_alias" \
    "FEATURE_BRANCH=$feature_branch" \
    "REPO_DIR=$repo_dir"

if [ "$prepare_only" = true ]; then
    printf '%s\n' \
        "Connect with: vers connect $vm_id" \
        "Run Codex with: vers exec -t 0 $vm_id sh -lc 'cd $repo_dir && codex'"
    exit 0
fi

wrapped_prompt=$(mktemp "${TMPDIR:-/tmp}/handle-task-prompt.XXXXXX")
trap 'rm -f "$wrapped_prompt"' EXIT HUP INT TERM

{
    printf '%s\n\n' \
        "You are the author agent for jq-experiment workstream '$workstream'." \
        "The prepared Git branch is '$feature_branch' based on '$base_branch'." \
        "Read AGENTS.md, docs/workstreams.md, and workstreams/$workstream.md before editing." \
        "Stay within assigned paths. Run focused checks and make validate." \
        "Commit and push the branch, then open or update a pull request. Never merge it." \
        "In the final response include the PR URL, commits, tests, evidence, and known gaps." \
        "Task:"
    cat "$prompt_file"
} >"$wrapped_prompt"

echo "Starting Codex in VM $vm_id"
if ! vers exec --ssh -i -t 7200 "$vm_id" env HOME=/root sh -lc \
    "export GH_TOKEN=\"\$GITHUB_API_KEY\"; cd '$repo_dir'; codex exec --dangerously-bypass-approvals-and-sandbox --color never -C '$repo_dir' -" \
    <"$wrapped_prompt"; then
    echo "Codex task failed; VM preserved for diagnosis: $vm_id" >&2
    exit 1
fi

echo "Task agent completed in VM $vm_id"
