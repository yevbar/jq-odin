# 0001: Diff-centric adversarial merge gate

- Status: accepted
- Date: 2026-07-29
- Workstream: integration

## Context and evidence

The GitHub credential available to Vers author agents can read commit statuses
but must not create or override them. The repository still needs one
fail-closed check before a pull request can merge.

Jane Street distinguishes patch-centric review of each commit from
diff-centric review between two history points. The latter removes noise from
intermediate fixups and reversals and handles the proposed net change as the
review unit:
<https://blog.janestreet.com/designing-a-code-review-tool-part-2-patches-or-diffs/>.

## Decision

Protect `main` with the single required check
`adversarial-diff-review`. GitHub Actions owns that check; agents do not write
commit statuses.

The workflow compares the pull request's base and head using Git's three-dot
merge-base diff. Its adversarial reviewer receives only that net diff, a path
manifest, immutable comparison metadata, and the trusted review policy. It
does not receive the author conversation, task prompt, commit messages, pull
request prose, intermediate patches, or a repository checkout.

The workflow is loaded from the protected base with `pull_request_target`.
The event is restricted to pull requests targeting `main`. Pull-request code
runs only in a separate validation job with no repository secrets. The review
job never executes pull-request code. Review policy and packet construction
come from the protected base revision, so a pull request cannot weaken the
gate that judges itself.

## Alternatives

- Per-commit patch review was rejected because fixups and reversals add noise
  without changing the proposed result.
- Giving the reviewer a complete checkout was rejected because it broadens
  both the review surface and prompt-injection surface.
- Letting Vers agents publish statuses was rejected because status-writing is
  unnecessary authority; GitHub Actions already reports workflow results.
- Treating the automated gate as a replacement for semantic and Odin-safety
  review lanes was rejected. Diff-only review intentionally cannot execute
  probes or establish facts absent from the diff.

## Consequences

- The repository needs an `OPENAI_API_KEY` Actions secret.
- Any validation failure, reviewer execution failure, malformed reviewer
  output, or reported finding fails closed.
- Branch protection must require an up-to-date
  `adversarial-diff-review` check and pull requests for `main`.
- Behavior-changing work still needs two fresh approvals for the independent
  Vers review lanes documented in `AGENTS.md`; those lanes are
  evidence-producing reviews, not required status writers.

## Validation

- Shell-parse and exercise the packet builder against repository revisions.
- Parse the workflow and reviewer JSON schema.
- Run `make validate`.
- Confirm branch protection names only `adversarial-diff-review`.
