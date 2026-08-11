# `isempty` literal-child compatibility shard

This bounded lane supports literal child filters: `isempty(empty)` returns
`true`, while scalar literals that emit one value return `false`. Generator,
dynamic, and error-producing child filters (including `range`) remain deferred.
