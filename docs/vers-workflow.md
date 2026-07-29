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
reviews the net merge-base-to-head diff in an isolated directory and fails
closed on validation errors, reviewer errors, or concrete findings. GitHub
Actions publishes the check result; the Vers `GITHUB_API_KEY` needs only read
access to observe it.

This automated diff-only gate does not replace the deeper lanes below, which
can inspect source context, execute probes, and submit evidence as pull-request
reviews.

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
head. The fixer pushes new commits to the feature branch, after which all CI
and adversarial lanes rerun. The integration coordinator merges only when:

- required CI passes;
- required independent reviews approve;
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
- two approving reviews, with stale approvals dismissed after new commits;
- approval by someone other than the last pusher;
- unresolved review conversations blocked;
- linear history required;
- force pushes and branch deletion disallowed.

Configure the `OPENAI_API_KEY` Actions secret before enabling protection. The
workflow uses trusted policy from the base branch, runs pull-request code only
in a secretless job, and gives the reviewer no repository checkout. The Vers
review lanes remain independent pull-request reviews rather than status
writers.
