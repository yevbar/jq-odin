# 0001: Diff-centric adversarial merge gate

- Status: accepted
- Date: 2026-07-29
- Workstream: integration

## Context and evidence

The GitHub credential available to Vers author agents can read commit statuses
but must not create or override them. The repository still needs one required
check before a pull request can merge, without transferring merge authority
from the integration coordinator to a review agent.

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

The workflow fails closed if validation fails or it cannot produce a valid,
current-head assessment. A finding does not itself fail the workflow. The
assessment includes a quality score, confidence, recommendation, and concrete
findings and is stored as a head-SHA-keyed artifact. The integration
coordinator judges that evidence and either starts a fresh fixer agent on the
existing task branch or merges the pull request as-is.

A `merge_as_is` assessment is structurally acceptable only with no findings,
quality at least 4, and medium or high confidence. This prevents an
environmental reviewer failure from becoming a successful empty assessment.

The trusted GitHub-hosted review job acts only as a controller. It restores the
approved authenticated Codex snapshot through the Vers REST API, uploads the
diff-only packet, runs Codex in that disposable VM, downloads the structured
assessment, and deletes the VM. The VM synchronizes its restored system clock
before TLS or agent operations. It receives neither the Vers API key nor a
repository checkout, and GitHub credentials are removed from its reviewer
process. The controller embeds the three review artifacts directly in the
model request, so review does not depend on shell-tool access and remains
usable on Vers kernels that do not support Codex's Linux seccomp sandbox.

## Alternatives

- Per-commit patch review was rejected because fixups and reversals add noise
  without changing the proposed result.
- Giving the reviewer a complete checkout was rejected because it broadens
  both the review surface and prompt-injection surface.
- Letting Vers agents publish statuses was rejected because status-writing is
  unnecessary authority; GitHub Actions already reports workflow results.
- Letting the reviewer recommendation directly accept or reject a pull
  request was rejected. Diff-only review intentionally cannot execute probes
  or establish facts absent from the diff.
- A self-hosted GitHub Actions runner in Vers was rejected for this gate. It
  requires runner registration, ephemeral-runner lifecycle management, and
  broader GitHub administration credentials without improving the diff-only
  review boundary.

## Consequences

- The repository needs a dedicated `VERS_API_KEY` Actions secret with only the
  VM permissions required by the controller. The authenticated Codex state
  remains in the approved Vers snapshot.
- Any validation failure, reviewer execution failure, malformed reviewer
  output, or missing current-head artifact fails closed.
- Branch protection must require an up-to-date
  `adversarial-diff-review` check and pull requests for `main`.
- The coordinator, not the author or reviewer, decides whether findings need a
  new task agent, deeper source-aware review, or no further implementation.

## Validation

- Shell-parse and exercise the packet builder against repository revisions.
- Parse the workflow and reviewer JSON schema.
- Run `make validate`.
- Confirm branch protection names only `adversarial-diff-review`.
