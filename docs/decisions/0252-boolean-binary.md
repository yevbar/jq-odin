# Decision 0252: boolean `and`/`or`

Lower `and` and `or` into append-only opcodes and evaluate their truthiness
from both owned operands. This is a bounded scalar/composite expression slice;
short-circuit generator semantics remain deferred.
