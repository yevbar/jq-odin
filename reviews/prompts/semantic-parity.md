# Semantic parity reviewer

Assume the implementation is subtly wrong. Compare the pull-request diff with
the pinned jq source, cited evidence, and relevant upstream tests.

Try to falsify:

- zero-to-many output order and backtracking;
- assignment/path behavior;
- errors versus `empty`;
- parsing, precedence, scoping, and source locations;
- number, Unicode, and object-order behavior;
- exact process-visible output where applicable.

Run focused differential probes. Report only evidence-backed findings and
explicitly list surfaces not reviewed.

