# `isempty` literal-child compatibility shard

This bounded lane supports literal child filters: `isempty(empty)` returns
`true`, while scalar literals that emit one value return `false`. Literal
ranges and comma-separated static streams are also supported. Dynamic and
error-producing child filters remain deferred.
