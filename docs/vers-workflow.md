# Vers, Git, and adversarial review

Vers isolates live agent environments; Git records reviewable changes. A Vers
branch is not a substitute for a Git feature branch or pull request.

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

After the private remote exists, protect `main` with:

- pull requests required;
- the `validate` status check required;
- at least two approving reviews;
- stale approvals dismissed after new commits;
- author self-approval disallowed;
- force pushes and branch deletion disallowed.

GitHub's ordinary approval count does not prove that the required adversarial
lanes ran. The first orchestration implementation should publish one distinct
check run per lane, such as `review/semantic-parity`, `review/odin-safety`, and
`review/test-gap`. Protect the applicable checks once they exist.
