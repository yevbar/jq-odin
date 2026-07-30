#!/bin/sh
set -eu

repo_url=${1:?repository URL is required}
base_branch=${2:?base branch is required}
feature_branch=${3:?feature branch is required}
repo_dir=${4:-/workspace/jq-experiment}

case "$base_branch" in
    *[!A-Za-z0-9._/-]*|'')
        echo "Invalid base branch: $base_branch" >&2
        exit 2
        ;;
esac

case "$feature_branch" in
    *[!A-Za-z0-9._/-]*|'')
        echo "Invalid feature branch: $feature_branch" >&2
        exit 2
        ;;
esac

sync_clock() {
    before=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if command -v chronyd >/dev/null 2>&1; then
        chronyd -q -t 20 "pool pool.ntp.org iburst" \
            >/tmp/handle-task-timesync.log 2>&1
    elif command -v ntpd >/dev/null 2>&1; then
        ntpd -gq >/tmp/handle-task-timesync.log 2>&1
    else
        server_date=$(
            curl -fsSI --max-time 15 http://github.com |
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
        date -u -s "$server_date" >/tmp/handle-task-timesync.log
    fi

    after=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "Clock synchronized: $before -> $after"
}

configure_github_credentials() {
    if [ -z "${GITHUB_API_KEY:-}" ]; then
        echo "GITHUB_API_KEY was not injected into the Vers VM" >&2
        exit 1
    fi

    helper_dir=/root/bin
    helper="$helper_dir/git-credential-github-env"
    mkdir -p "$helper_dir"
    printf '%s\n' \
        '#!/bin/sh' \
        'case "$1" in' \
        '    get)' \
        '        printf "username=x-access-token\\npassword=%s\\n" "$GITHUB_API_KEY"' \
        '        ;;' \
        'esac' >"$helper"
    chmod 700 "$helper"
    git config --global credential.https://github.com.helper "$helper"
}

sync_repository() {
    mkdir -p "$(dirname -- "$repo_dir")"

    if [ ! -d "$repo_dir/.git" ]; then
        git clone --recurse-submodules "$repo_url" "$repo_dir"
    fi

    git -C "$repo_dir" remote set-url origin "$repo_url"
    git -C "$repo_dir" fetch --prune --tags origin \
        '+refs/heads/*:refs/remotes/origin/*'

    if ! git -C "$repo_dir" show-ref --verify --quiet \
        "refs/remotes/origin/$base_branch"; then
        echo "Remote base branch does not exist: origin/$base_branch" >&2
        exit 1
    fi

    if git -C "$repo_dir" show-ref --verify --quiet \
        "refs/heads/$feature_branch"; then
        git -C "$repo_dir" switch "$feature_branch"
        git -C "$repo_dir" merge --ff-only "origin/$feature_branch"
    elif git -C "$repo_dir" show-ref --verify --quiet \
        "refs/remotes/origin/$feature_branch"; then
        git -C "$repo_dir" switch -c "$feature_branch" --track \
            "origin/$feature_branch"
    else
        git -C "$repo_dir" switch -c "$feature_branch" \
            "origin/$base_branch"
    fi

    git -C "$repo_dir" submodule sync --recursive
    git -C "$repo_dir" submodule update --init --recursive
}

configure_identity() {
    if command -v gh >/dev/null 2>&1; then
        export GH_TOKEN=${GH_TOKEN:-$GITHUB_API_KEY}
        login=$(gh api user --jq .login)
        user_id=$(gh api user --jq .id)
        git -C "$repo_dir" config user.name "$login"
        git -C "$repo_dir" config user.email \
            "$user_id+$login@users.noreply.github.com"
        gh auth status
    fi
}

configure_worker() {
    worker_user=jqagent
    worker_home=/home/jqagent
    worker_codex_root=/opt/codex-worker

    if ! id "$worker_user" >/dev/null 2>&1; then
        useradd --create-home --shell /bin/sh "$worker_user"
    fi

    codex_js=$(readlink -f "$(command -v codex)")
    codex_package=$(CDPATH= cd -- "$(dirname -- "$codex_js")/.." && pwd)
    node_binary=$(readlink -f "$(command -v node)")
    install -d -m 755 "$worker_codex_root"
    if [ ! -d "$worker_codex_root/package" ]; then
        cp -a --link "$codex_package" "$worker_codex_root/package"
    fi
    if [ ! -f "$worker_codex_root/node" ]; then
        ln "$node_binary" "$worker_codex_root/node"
    fi
    printf '%s\n' \
        '#!/bin/sh' \
        'exec /opt/codex-worker/node /opt/codex-worker/package/bin/codex.js "$@"' \
        >/usr/local/bin/codex-worker
    chmod 755 /usr/local/bin/codex-worker

    install -d -m 700 -o "$worker_user" -g "$worker_user" \
        "$worker_home/.codex" "$worker_home/bin"
    install -m 600 -o "$worker_user" -g "$worker_user" \
        /root/.codex/auth.json "$worker_home/.codex/auth.json"
    if [ -f /root/.codex/config.toml ]; then
        install -m 600 -o "$worker_user" -g "$worker_user" \
            /root/.codex/config.toml "$worker_home/.codex/config.toml"
    fi

    worker_helper="$worker_home/bin/git-credential-github-env"
    install -m 700 -o "$worker_user" -g "$worker_user" \
        /root/bin/git-credential-github-env "$worker_helper"
    runuser -u "$worker_user" -- env HOME="$worker_home" \
        git config --global credential.https://github.com.helper "$worker_helper"

    chown -R "$worker_user:$worker_user" "$repo_dir"
    git config --global --add safe.directory "$repo_dir"
}

sync_clock
configure_github_credentials
sync_repository
"$repo_dir/scripts/vers/bootstrap-vm.sh"
configure_identity
configure_worker

printf '%s\n' \
    "Repository ready: $repo_dir" \
    "Branch: $feature_branch" \
    "HEAD: $(git -C "$repo_dir" rev-parse HEAD)"
