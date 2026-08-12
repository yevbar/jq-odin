# Literal `in` and `inside`

Literal array and object operands for `in(...)` and `inside(...)` reuse the
existing `has` and recursive `contains` kernels. Dynamic/generator operands
remain deferred.

Oracle evidence: `upstream/jq/src/builtin.jq:182-183`.
