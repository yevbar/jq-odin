# `abs` container passthrough compatibility shard

This shard covers jq's `abs` behavior for array and object inputs, which are
returned unchanged. It also keeps string identity and numeric magnitude in the
same oracle fixture. Boolean and null inputs remain numeric-type errors, and
`fabs` remains numeric-only.

The numeric family is anchored at `upstream/jq/tests/jq.test:2212-2229`.
Container passthrough was confirmed against the pinned jq 1.8.1 oracle with
`[] | abs` and `{a:[1,2]} | abs`.
