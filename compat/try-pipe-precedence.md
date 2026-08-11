# `try`/`catch` pipe precedence compatibility shard

An unparenthesized catch branch stops before a same-level comma or following
pipe. This lets jq's surrounding stream operators apply to the complete set of
caught results, rather than only to the final catch branch.

The focused regression is `upstream/jq/tests/jq.test:2467`.
