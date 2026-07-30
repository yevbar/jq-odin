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
vers_bin=${VERS_BIN:-vers}

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

for dependency in "$vers_bin" jq; do
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
job_script="$skill_dir/scripts/run-job.sh"
codex_script="$skill_dir/scripts/run-codex.sh"
launch_script="$skill_dir/scripts/launch-job.sh"
inspect_script="$skill_dir/scripts/inspect-job.sh"

wait_for_remote_job() {
    job_name=$1
    status_file=$2
    log_file=$3
    pid_file="${status_file}.pid"
    inspection_failures=0

    while :; do
        if inspection_output=$(
            "$vers_bin" exec -t 60 "$vm_id" "$remote_inspector" \
                "$status_file" "$pid_file"
        ); then
            state=$(
                printf '%s\n' "$inspection_output" |
                sed -n '/^starting$/p; /^running$/p; /^runner-gone$/p; /^[0-9][0-9]*$/p' |
                sed -n '$p'
            )
        else
            state=
        fi

        if [ -z "$state" ]; then
            inspection_failures=$((inspection_failures + 1))
            if [ "$inspection_failures" -ge 6 ]; then
                echo "Unable to inspect $job_name after 6 consecutive attempts" >&2
                status=124
                break
            fi
            echo "Unable to inspect $job_name; retrying ($inspection_failures/6)" >&2
            sleep 10
            continue
        fi
        inspection_failures=0

        case "$state" in
            [0-9]*)
                status=$state
                break
                ;;
            runner-gone)
                status=125
                echo "$job_name runner exited without recording status" >&2
                break
                ;;
            *)
                echo "Waiting for $job_name in VM $vm_id"
                ;;
        esac
        sleep 10
    done

    "$vers_bin" exec -t 60 "$vm_id" tail -n 240 "$log_file" || true
    if [ "$status" -ne 0 ]; then
        echo "$job_name failed with status $status" >&2
        return "$status"
    fi
}

echo "Booting Vers commit $commit_key"
run_output=$(
    "$vers_bin" run-commit "$commit_key" \
        --vm-alias "$vm_alias" \
        --wait
)
printf '%s\n' "$run_output"
vm_id=$(
    printf '%s\n' "$run_output" |
        sed -n "s/.*VM '\\([0-9a-f-][0-9a-f-]*\\)'.*/\\1/p" |
        sed -n '1p'
)
if [ -z "$vm_id" ]; then
    echo "Unable to parse VM ID from vers run-commit output" >&2
    exit 1
fi

current_disk_kib=$(
    "$vers_bin" exec --ssh -t 60 "$vm_id" env HOME=/root sh -lc \
        "df -Pk / | awk 'NR == 2 { print \$2 }'" |
        sed -n '/^[0-9][0-9]*$/p' |
        sed -n '$p'
)
if [ -z "$current_disk_kib" ]; then
    echo "Unable to determine VM disk size" >&2
    exit 1
fi
current_disk_mib=$((current_disk_kib / 1024))
if [ "$current_disk_mib" -lt "$disk_size_mib" ]; then
    echo "Growing VM disk: ${current_disk_mib} MiB -> ${disk_size_mib} MiB"
    "$vers_bin" resize "$vm_id" --size "$disk_size_mib"
fi

echo "Preparing VM $vm_id"
remote_prepare=/tmp/handle-task-prepare-vm.sh
remote_job=/tmp/handle-task-run-job.sh
remote_launcher=/tmp/handle-task-launch-job.sh
remote_inspector=/tmp/handle-task-inspect-job.sh
remote_state_dir=/run/handle-task
prepare_status=$remote_state_dir/prepare.status
prepare_log=$remote_state_dir/prepare.log
"$vers_bin" exec -t 60 "$vm_id" mkdir -p "$remote_state_dir"
"$vers_bin" exec -t 60 "$vm_id" chmod 700 "$remote_state_dir"
"$vers_bin" copy -t 120 "$vm_id" "$prepare_script" "$remote_prepare"
"$vers_bin" copy -t 120 "$vm_id" "$job_script" "$remote_job"
"$vers_bin" copy -t 120 "$vm_id" "$launch_script" "$remote_launcher"
"$vers_bin" copy -t 120 "$vm_id" "$inspect_script" "$remote_inspector"
"$vers_bin" exec -t 60 "$vm_id" chmod 700 \
    "$remote_prepare" "$remote_job" "$remote_launcher" "$remote_inspector"
"$vers_bin" exec -t 60 "$vm_id" "$remote_launcher" \
    "$remote_state_dir/prepare-launch.log" \
    "$remote_job" "$prepare_status" "$prepare_log" \
    env HOME=/root sh "$remote_prepare" \
    "$repo_url" "$base_branch" "$feature_branch" "$repo_dir"
if ! wait_for_remote_job "VM preparation" "$prepare_status" "$prepare_log"; then
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
        "Connect with: $vers_bin connect $vm_id" \
        "Run Codex with: $vers_bin exec -t 0 $vm_id runuser -u jqagent -- env HOME=/home/jqagent sh -lc 'cd $repo_dir && codex'"
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
remote_prompt=/tmp/handle-task-prompt.txt
remote_codex=/tmp/handle-task-run-codex.sh
codex_status=$remote_state_dir/codex.status
codex_log=$remote_state_dir/codex.log
"$vers_bin" copy -t 120 "$vm_id" "$wrapped_prompt" "$remote_prompt"
"$vers_bin" copy -t 120 "$vm_id" "$codex_script" "$remote_codex"
"$vers_bin" exec -t 60 "$vm_id" chmod 755 "$remote_codex"
"$vers_bin" exec -t 60 "$vm_id" chown jqagent:jqagent "$remote_prompt"
"$vers_bin" exec -t 60 "$vm_id" chmod 600 "$remote_prompt"
"$vers_bin" exec -t 60 "$vm_id" "$remote_launcher" \
    "$remote_state_dir/codex-launch.log" \
    "$remote_job" "$codex_status" "$codex_log" \
    runuser -u jqagent -- env HOME=/home/jqagent \
    "$remote_codex" "$repo_dir" "$remote_prompt"
if ! wait_for_remote_job "Codex task" "$codex_status" "$codex_log"; then
    echo "Codex task failed; VM preserved for diagnosis: $vm_id" >&2
    exit 1
fi

echo "Task agent completed in VM $vm_id"
