---
name: handle-task
description: Launch and supervise one jq-to-Odin implementation task in an isolated Vers VM, then coordinate its pull request using the required adversarial diff assessment. Use when asked to handle, dispatch, start, resume, implement, assess, fix, or decide whether to merge a jq rewrite task on Vers.
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

- requires the current Vers CLI with `run-commit`, `execute`, and `copy`; set
  `VERS_BIN` to an alternate verified binary path when needed;
- deliberately targets the Linux Vers runtime and requires util-linux
  `flock(1)` in addition to Linux `/proc` process identities;
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

VM preparation and Codex run as durable in-VM jobs with polled status files.
This prevents a local API request deadline or transient client disconnect from
terminating a long-running author task. Each status file has a recoverable
launch claim. The durable child atomically publishes its reuse-safe identity
(PID plus Linux process start time) before it runs the job; retries preserve
completed or committed launches and recognize a live initial launcher without
reclaiming it. A launch is acknowledged only when a completed status or
committed runner identity exists; bounded observation of a live but uncommitted
owner fails closed so the controller retries. If an initial launcher dies
before identity publication, retries observe the claim for a bounded interval
and then replace its generation under a kernel-managed advisory lock on a
stable file. Contenders bound acquisition and never unlink or recreate the
lock path; process/FD teardown releases the lock after interruption. A delayed
child must validate its generation under the same lock, so it cannot run after
a replacement has been authorized. The launcher closes the lock FD before
durable fork and runner exec, and fails closed if a committed runner disappears
before recording its status.
Preparation runs as root, but Codex and repository commands run as the
unprivileged `jqagent` user. Root-owned status files live under
`/run/handle-task`, so reviewed code cannot forge task completion.

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

The launcher deletes a VM only after a successful non-interactive task. Any
failed or interrupted VM, including a preparation failure, is paused so its
disk can be inspected or checkpointed without consuming running-VM capacity.
If pausing fails, the launcher reports that the VM remains running and never
silently deletes it. `--prepare-only` retains its interactive VM by design.

Use `--keep-vm` only when the coordinator explicitly needs a running VM after
the launcher exits. Capture its reported VM ID, branch, and PR URL. If an agent
is paused after failure:

- resume it before using `vers execute <vm-id> ...` or `vers connect <vm-id>`;
- preserve it for diagnosis or checkpoint it with `vers commit create <vm-id>`;
- never silently relaunch the same task on another branch;
- delete it when its useful state is pushed or checkpointed.

Before reporting author completion, verify the pull request exists, CI has
started, and the author did not merge it. The author may observe
`adversarial-diff-review` with read-only status access but must never create,
override, or spoof that check.

## Decide the pull request

Keep disposition with the top-level integration coordinator. After the
required check completes. The check itself runs the diff-only adversarial
review in a disposable Vers VM restored from the approved authenticated
snapshot; it is not a self-hosted Actions runner.

1. Confirm the repository has a dedicated `VERS_API_KEY` Actions secret. Never
   copy that token into an author or reviewer prompt.
2. Verify `adversarial-diff-review` succeeded for the current PR head.
3. Read the exact-head assessment:

    ```sh
    scripts/read-assessment.sh --pr <number>
    ```

4. Inspect the assessment evidence, author handoff, test results, affected
   contracts, and risk. Treat `merge_as_is` or `task_agent` as advice, not an
   automatic decision.
5. Choose one outcome:
   - launch a fresh agent in a fresh Vers VM on the existing
     `agent/<workstream>/<task>` branch, giving it only accepted findings and
     acceptance checks; or
   - merge the pull request as-is when the evidence supports it and all
     repository gates pass.

Never ask the author agent or adversarial reviewer to merge. Never reuse the
author VM for a fixer. A fixer pushes to the same feature branch so validation
and assessment rerun against the new head. Do not read or accept an artifact
whose name does not contain the current PR head SHA.

Dispatch source-aware semantic-parity, Odin-safety, or test-gap reviewers in
fresh VMs when the diff assessment or risk cannot be resolved from the packet.
