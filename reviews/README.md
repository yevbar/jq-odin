# Adversarial reviews

Reviewer agents use one prompt from `reviews/prompts/` in a fresh environment.
They post findings on the pull request; they do not edit the author branch.

These source-aware Vers reviews complement the required automated
`adversarial-diff-review` gate. The automated reviewer is intentionally
limited to the net diff; these lanes may inspect the immutable pull-request
commit, run tests, and construct new fixtures when the integration coordinator
decides more evidence is needed.

Each finding includes severity, file and line, violated behavior or invariant,
evidence, a reproduction command or test, and the smallest credible remedy.
An approval states what was examined and which commands ran.
