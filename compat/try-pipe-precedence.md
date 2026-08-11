# `try`/`catch` pipe precedence compatibility shard

An unparenthesized catch branch stops before a following pipe. This lets jq's
pipe apply to the complete comma stream of caught results, rather than only to
the second catch branch.

The focused regression is `upstream/jq/tests/jq.test:2467`.
