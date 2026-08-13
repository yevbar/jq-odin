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
  --keep-vm           Keep the VM running after this command exits
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
keep_vm=false
vers_bin=${VERS_BIN:-vers}
vm_id=
vm_phase=not-created
wrapped_prompt=
vm_alias=

finish() {
    status=$?
    trap - EXIT HUP INT TERM

    if [ -n "$wrapped_prompt" ]; then
        rm -f "$wrapped_prompt"
    fi

    if [ -z "$vm_id" ] && [ "$vm_phase" = creating ] &&
       [ -n "$vm_alias" ]; then
        # run-commit can create the VM and then lose its response. Resolve the
        # unique alias so an interrupted controller does not leak that VM.
        resolved_vm_id=$("$vers_bin" alias "$vm_alias" 2>/dev/null || true)
        case "$resolved_vm_id" in
            *[!0-9a-f-]*|'')
                ;;
            *)
                vm_id=$resolved_vm_id
                ;;
        esac
    fi

    if [ -z "$vm_id" ]; then
        exit "$status"
    fi

    if [ "$keep_vm" = true ]; then
        echo "Keeping VM $vm_id because --keep-vm was requested"
        exit "$status"
    fi

    case "$vm_phase" in
        completed)
            echo "Deleting completed task VM $vm_id"
            if ! "$vers_bin" delete -y "$vm_id"; then
                echo "Failed to delete completed task VM $vm_id" >&2
                status=1
            fi
            ;;
        prepared)
            if [ "$prepare_only" = true ]; then
                # --prepare-only is an explicit request for an interactive VM.
                echo "Interactive VM retained: $vm_id"
            else
                echo "Pausing failed or interrupted task VM $vm_id" >&2
                if ! "$vers_bin" pause "$vm_id"; then
                    echo "Unable to pause task VM; it has been retained for diagnosis: $vm_id" >&2
                    status=1
                fi
            fi
            ;;
        *)
            echo "Pausing failed or interrupted task VM $vm_id" >&2
            if ! "$vers_bin" pause "$vm_id"; then
                echo "Unable to pause task VM; it has been retained for diagnosis: $vm_id" >&2
                status=1
            fi
            ;;
    esac

    exit "$status"
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

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
        --keep-vm)
            keep_vm=true
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
vm_alias="jq-$workstream-$task_slug-$alias_suffix-$$"
skill_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
prepare_script="$skill_dir/scripts/prepare-vm.sh"
job_script="$skill_dir/scripts/run-job.sh"
codex_script="$skill_dir/scripts/run-codex.sh"
launch_script="$skill_dir/scripts/launch-job.sh"
inspect_script="$skill_dir/scripts/inspect-job.sh"

copy_to_vm() (
    source_path=$1
    remote_path=$2
    expected_bytes=$(wc -c <"$source_path" | tr -d '[:space:]')
    attempt=1

    while [ "$attempt" -le 3 ]; do
        if "$vers_bin" copy "$vm_id" \
            "$source_path" "$remote_path"; then
            remote_bytes=$(
                "$vers_bin" execute "$vm_id" \
                    sh -c 'wc -c <"$1"' sh "$remote_path" 2>/dev/null |
                    sed -n '/^[[:space:]]*[0-9][0-9]*[[:space:]]*$/p' |
                    tr -d '[:space:]' |
                    sed -n '$p'
            ) || remote_bytes=
            if [ "$remote_bytes" = "$expected_bytes" ]; then
                return 0
            fi
        else
            remote_bytes=
        fi

        printf 'Copy verification failed for %s (attempt %s/3, expected %s bytes, got %s)\n' \
            "$remote_path" "$attempt" "$expected_bytes" \
            "${remote_bytes:-unknown}" >&2
        attempt=$((attempt + 1))
        if [ "$attempt" -le 3 ]; then
            sleep "${HANDLE_TASK_COPY_RETRY_DELAY:-2}"
        fi
    done

    echo "Unable to copy a complete helper to $remote_path" >&2
    return 1
)

launch_remote_job() (
    launch_job_name=$1
    shift
    launch_attempt=1

    while [ "$launch_attempt" -le 3 ]; do
        if "$vers_bin" execute "$vm_id" sh "$remote_launcher" "$@"; then
            return 0
        fi

        printf '%s launch acknowledgement failed (attempt %s/3)\n' \
            "$launch_job_name" "$launch_attempt" >&2
        launch_attempt=$((launch_attempt + 1))
        if [ "$launch_attempt" -le 3 ]; then
            sleep "${HANDLE_TASK_LAUNCH_RETRY_DELAY:-2}"
        fi
    done

    echo "Unable to acknowledge $launch_job_name launch after 3 attempts" >&2
    return 1
)

wait_for_remote_job() {
    job_name=$1
    status_file=$2
    log_file=$3
    runner_identity_file="${status_file}.pid"
    inspection_failures=0

    while :; do
        if inspection_output=$(
            "$vers_bin" execute "$vm_id" sh "$remote_inspector" \
                "$status_file" "$runner_identity_file"
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

    "$vers_bin" execute "$vm_id" tail -n 240 "$log_file" || true
    if [ "$status" -ne 0 ]; then
        echo "$job_name failed with status $status" >&2
        return "$status"
    fi
}

echo "Booting Vers commit $commit_key"
vm_phase=creating
run_output=$(
    "$vers_bin" run-commit "$commit_key" \
        --vm-alias "$vm_alias"
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
vm_phase=booted

current_disk_kib=$(
    "$vers_bin" execute "$vm_id" env HOME=/root sh -lc \
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
    echo "VM disk is ${current_disk_mib} MiB; current Vers CLI has no resize command, continuing with the provisioned disk" >&2
fi

echo "Preparing VM $vm_id"
remote_prepare=/tmp/handle-task-prepare-vm.sh
remote_job=/tmp/handle-task-run-job.sh
remote_launcher=/tmp/handle-task-launch-job.sh
remote_inspector=/tmp/handle-task-inspect-job.sh
remote_state_dir=/run/handle-task
prepare_status=$remote_state_dir/prepare.status
prepare_log=$remote_state_dir/prepare.log
"$vers_bin" execute "$vm_id" mkdir -p "$remote_state_dir"
"$vers_bin" execute "$vm_id" chmod 700 "$remote_state_dir"
copy_to_vm "$prepare_script" "$remote_prepare"
copy_to_vm "$job_script" "$remote_job"
copy_to_vm "$launch_script" "$remote_launcher"
copy_to_vm "$inspect_script" "$remote_inspector"
"$vers_bin" execute "$vm_id" chmod 700 \
    "$remote_prepare" "$remote_job" "$remote_launcher" "$remote_inspector"
launch_remote_job "VM preparation" \
    "$remote_state_dir/prepare-launch.log" \
    "$remote_job" "$prepare_status" "$prepare_log" \
    env HOME=/root sh "$remote_prepare" \
    "$repo_url" "$base_branch" "$feature_branch" "$repo_dir"
if ! wait_for_remote_job "VM preparation" "$prepare_status" "$prepare_log"; then
    echo "VM preparation failed: $vm_id" >&2
    exit 1
fi
vm_phase=prepared

printf '%s\n' \
    "VM_ID=$vm_id" \
    "VM_ALIAS=$vm_alias" \
    "FEATURE_BRANCH=$feature_branch" \
    "REPO_DIR=$repo_dir"

if [ "$prepare_only" = true ]; then
    printf '%s\n' \
        "Connect with: $vers_bin connect $vm_id" \
        "Run Codex with: $vers_bin execute $vm_id runuser -u jqagent -- env HOME=/home/jqagent sh -lc 'cd $repo_dir && codex'"
    exit 0
fi

wrapped_prompt=$(mktemp "${TMPDIR:-/tmp}/handle-task-prompt.XXXXXX")

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
vm_phase=codex
remote_prompt=/tmp/handle-task-prompt.txt
remote_codex=/tmp/handle-task-run-codex.sh
codex_status=$remote_state_dir/codex.status
codex_log=$remote_state_dir/codex.log
copy_to_vm "$wrapped_prompt" "$remote_prompt"
copy_to_vm "$codex_script" "$remote_codex"
"$vers_bin" execute "$vm_id" chmod 755 "$remote_codex"
"$vers_bin" execute "$vm_id" chown jqagent:jqagent "$remote_prompt"
"$vers_bin" execute "$vm_id" chmod 600 "$remote_prompt"
launch_remote_job "Codex task" \
    "$remote_state_dir/codex-launch.log" \
    "$remote_job" "$codex_status" "$codex_log" \
    runuser -u jqagent -- env HOME=/home/jqagent \
    sh "$remote_codex" "$repo_dir" "$remote_prompt"
if ! wait_for_remote_job "Codex task" "$codex_status" "$codex_log"; then
    echo "Codex task failed: $vm_id" >&2
    exit 1
fi

vm_phase=completed
echo "Task agent completed in VM $vm_id"
