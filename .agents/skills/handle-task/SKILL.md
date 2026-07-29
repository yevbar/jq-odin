---
name: handle-task
description: Launch and supervise one jq-to-Odin implementation task in an isolated Vers VM with authenticated Codex, current GitHub branch state, a dedicated agent feature branch, the pinned toolchain, and repository validation. Use when asked to handle, dispatch, start, resume, or implement a jq rewrite task on Vers, especially when the result should become a pull request.
---

# Handle Task

Launch one author agent from the authenticated Codex snapshot. Keep Git history
as the review boundary and Vers as the compute boundary.

## Prepare the task

1. Read the repository `AGENTS.md`, `docs/workstreams.md`, and the selected
   `workstreams/<id>.md`.
2. Choose exactly one workstream and a lowercase hyphenated task slug.
3. Confirm the requested changes fit the workstream-owned paths. Escalate
   shared-contract or coordinator-owned changes instead of broadening scope.
4. Write a self-contained task prompt to a temporary file. Include:
   - outcome and acceptance criteria;
   - workstream and owned paths;
   - relevant upstream jq evidence or fixtures;
   - required focused checks;
   - instruction to run `make validate`, commit, push, and open a PR;
   - instruction never to merge its own PR.

Do not put credentials in the prompt or command line.

## Launch

Run the bundled launcher from the skill directory:

```sh
scripts/handle-task.sh \
  --workstream <workstream-id> \
  --task <task-slug> \
  --prompt-file <absolute-prompt-path>
```

The launcher:

- boots the Vers commit named by `JQ_CODEX_VERS_COMMIT`, defaulting to the
  repository's approved authenticated snapshot;
- synchronizes the restored clock before TLS or package operations;
- uses `GITHUB_API_KEY` through an environment-backed Git credential helper;
- clones or fetches every GitHub branch and prunes deleted remote branches;
- grows the task filesystem to at least 8 GiB by default;
- checks out or creates `agent/<workstream>/<task>` from the latest base;
- initializes submodules and the pinned Odin toolchain;
- validates the repository;
- invokes authenticated Codex non-interactively inside the VM.

Use `--prepare-only` instead of `--prompt-file` to prepare a VM for interactive
access:

```sh
scripts/handle-task.sh \
  --workstream <workstream-id> \
  --task <task-slug> \
  --prepare-only
```

Override the integration base with `--base <branch>` and the snapshot with
`--commit <vers-commit-key>` only when the task explicitly requires it. Use
`--disk-size <mib>` when a task needs more than the default 8 GiB.

## Supervise and hand off

The launcher intentionally leaves the VM running. Capture its reported VM ID,
branch, and PR URL. If the agent fails:

- inspect it with `vers exec <vm-id> ...` or `vers connect <vm-id>`;
- preserve it for diagnosis or checkpoint it with `vers commit create <vm-id>`;
- never silently relaunch the same task on another branch;
- delete it only when the user or coordinator confirms it is no longer needed.

Before reporting completion, verify the pull request exists, CI has started,
and the author did not merge it. Adversarial-review agents use separate fresh
VMs and the review prompts in the repository; they are not launched from the
author VM.
