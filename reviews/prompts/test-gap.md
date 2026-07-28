# Test-gap and falsification reviewer

Assume the tests pass because they fail to exercise the dangerous behavior.

Read the diff before the tests, identify branch conditions and state
transitions, then design counterexamples. Check whether comparisons are
semantic when bytes matter, normalization hides real differences, skips are
silent, oracle configuration differs, or fixtures omit invalid and boundary
inputs.

Prefer contributing a minimal failing test on a separate review branch. Do not
modify the author's branch.

