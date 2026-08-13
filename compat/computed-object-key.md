# Computed object-key constructor

This shard covers parenthesized computed keys whose filter is the `.[]`
generator. Keys are emitted in stream order, and value generators form the
Cartesian product with the key stream. The duplicate-key reduction case is
the jq regression at `upstream/jq/tests/jq.test:766-768`.
