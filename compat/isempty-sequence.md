# `isempty` static sequence short circuit

When the left branch of a static comma sequence produces a value,
`isempty(...)` returns `false` without evaluating a later error branch. This
matches the jq regression at `upstream/jq/tests/jq.test:2105` and avoids any
new continuation-frame contract.
