# Vers, Git, and adversarial review

Vers isolates live agent environments; Git records reviewable changes. A Vers
branch is not a substitute for a Git feature branch or pull request.

## Handle-task skill

Invoke the repository-local `$handle-task` skill to prepare and run one author
task. Its launcher uses the authenticated Codex Vers snapshot, synchronizes the
restored clock, fetches all current GitHub branch state, creates or resumes the
assigned `agent/<workstream>/<task>` branch, installs the pinned toolchain, and
runs Codex.

The approved default snapshot is:

```text
13b7c648-7849-4b9b-a788-16b4522edeb8
```

Override it with `JQ_CODEX_VERS_COMMIT` only after validating and approving a
replacement snapshot. `GITHUB_API_KEY` is injected by Vers and is never stored
in the image or repository.

## Golden environment

Create one clean Linux VM, install the pinned toolchain, clone the repository
with submodules, and run `make validate`. Run
`scripts/vers/bootstrap-vm.sh` inside the VM for host prerequisites and Odin.

Before making a Vers commit:

- remove credentials, shell history, logs, and transient outputs;
- clear `/etc/environment`;
- stop agent processes;
- regenerate SSH host keys;
- confirm `.tools/` contains the pinned Odin release;
- run `make validate`.

Secrets are injected into new VMs with `vers env`; they must not be captured in
the golden snapshot. Record the approved golden commit ID outside source
control or as a non-secret Vers repository tag.

## Author loop

1. Boot or branch a worker from the clean golden commit.
2. In that VM, fetch the integration base and create
   `agent/<workstream>/<task>`.
3. Give the agent `AGENTS.md`, its workstream brief, acceptance tests, and
   owned paths.
4. Require small commits and `make validate` before push.
5. Open a pull request using the repository template.

Useful Vers primitives:

```sh
vers run-commit <golden-commit> -N jq-author-<task> --wait
vers exec jq-author-<task> git -C <repo-path> status
vers commit create jq-author-<task>
```

The last command is a recoverable checkpoint of the entire live worker, not a
replacement for Git commits.

## Review loop

The required `adversarial-diff-review` GitHub Actions check runs first. It
reviews the net merge-base-to-head diff in an isolated directory and preserves
a quality score, recommendation, and findings for the exact PR head. It fails
closed on validation, reviewer, schema, or artifact errors—not merely because
the reviewer found a defect. GitHub Actions publishes the check result; the
Vers `GITHUB_API_KEY` needs only read access to observe it.

The GitHub-hosted review job is a Vers API controller, not a persistent
self-hosted runner. It uses a dedicated `VERS_API_KEY` Actions secret to
restore the approved snapshot, upload only the review packet, execute the
already-authenticated Codex reviewer, retrieve its JSON result, and delete the
VM. The token stays on the GitHub runner. The disposable VM synchronizes time,
removes any stale author checkout at the approved snapshot path, and unsets
GitHub credentials before review.

A separate GitHub job mirrors the validated assessment into a bot-authored,
head-specific pull-request comment. It updates only the comment for the same
head and skips publication when that head is no longer current, preventing a
slow older workflow from replacing newer review output. It has
`pull-requests: write` and `actions: read`, but no Vers secret. The exact-head
artifact remains authoritative; each comment is a human-readable projection.

The top-level integration coordinator reads that artifact and owns the
decision. It may merge as-is, launch a fresh fixer agent on the same task
branch, or request deeper lanes below to inspect context and execute probes.

Do not branch reviewers from the author's live VM. A Vers branch preserves
memory and running processes, which would also preserve author-agent context.

For each review lane:

1. Start a fresh VM from the clean golden commit.
2. Fetch and check out the immutable pull-request head commit.
3. Start a new agent session with exactly one prompt from `reviews/prompts/`.
4. Run tests and create additional adversarial cases without editing the
   author's branch.
5. Submit a GitHub pull-request review with evidence and reproduction commands.

Required lanes:

- semantic parity;
- Odin ownership and safety;
- test-gap/falsification for high-risk changes.

Reviewer disagreement is resolved by evidence: a failing test, an upstream
source citation, or an accepted design decision. The author does not merely
vote down a finding.

## Fix and merge loop

Accepted findings are handled by a fixer agent in a fresh VM based on the PR
head. The fixer pushes new commits to the existing feature branch, after which
validation and the diff assessment rerun. The integration coordinator may
instead merge as-is when the recommendation or findings do not withstand the
full evidence. In either case, only the coordinator decides. It merges only
when:

- required CI passes;
- evidence and ownership shards are updated;
- no unresolved high-severity finding remains;
- the PR is rebased or otherwise tested against the current integration base.

This follows the useful part of the reported Bun rewrite pattern: facts before
plans, isolated parallel implementers, and separate agents instructed to
falsify changes rather than confirm them.

## GitHub repository settings

Protect `main` with:

- pull requests required;
- the single `adversarial-diff-review` check required and strictly up to date;
- unresolved review conversations blocked;
- linear history required;
- force pushes and branch deletion disallowed.

Configure a dedicated `VERS_API_KEY` Actions secret before enabling
protection. The workflow uses trusted policy from the base branch, runs
pull-request code only in a secretless job, gives the reviewer no repository
checkout, and preserves the assessment for the coordinator rather than making
the reviewer the merge authority.
