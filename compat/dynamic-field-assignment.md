# Bounded dynamic object-field assignment

This shard covers filter-valued object assignment for a single static field:
`.name = FILTER`, where `FILTER` is identity, a field lookup, or a scalar
literal. The candidate evaluates the bounded RHS against the original input
and applies copy-on-write object replacement, including creation of a missing
key. Generator-valued RHS filters remain outside this slice until evaluator
continuation frames can preserve all produced updates.
