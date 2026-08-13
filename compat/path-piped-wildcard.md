# Piped wildcard path compatibility shard

This shard covers the bounded path continuation `path(.a | .[])`. jq treats
the empty-field iterator on the right side of a pipe as a dynamic path beneath
the static `.a` prefix, yielding one path per array element. The `try` wrapper
must preserve successful outputs while remaining available for runtime path
errors.

The upstream path corpus includes nearby generator-valued path cases at
`upstream/jq/tests/jq.test:1110-1128`; arbitrary `map(select(...))` continuations
remain outside this bounded slice and require general resumable filters.
