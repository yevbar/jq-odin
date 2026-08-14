# modulemeta scalar projection bridge

The driver currently supports the two scalar projections `modulemeta | .deps |
length` and `modulemeta | .defs | length` using the owned module metadata
extractor. The full metadata object and arbitrary projections remain deferred
until module context has a first-class runtime representation.

The expected values come from jq 1.8.1's module fixture `upstream/jq/tests/modules/c/c.jq`
and the `modulemeta` behavior exercised by `upstream/jq/tests/jq.test`.
