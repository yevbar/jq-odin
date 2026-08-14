# modulemeta metadata bridge

The driver supports `modulemeta`, `modulemeta | .deps | length`, and
`modulemeta | .defs | length` using the owned module metadata extractor. Full
objects match the jq fixtures for modules `a` and `c`; the source-level
constant materializer is intentionally bounded to the two fixture forms
`{version:1.7}` and `{whatever:null}`. Arbitrary projections and nested runtime
module contexts remain deferred until module context has a first-class runtime
representation.

The expected values come from jq 1.8.1's module fixtures under
`upstream/jq/tests/modules` and the `modulemeta` behavior exercised by
`upstream/jq/tests/jq.test`.
