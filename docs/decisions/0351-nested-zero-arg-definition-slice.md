# Bounded nested zero-argument definitions

The parser now keeps zero-argument declarations in source form and builds
direct immutable `Call` body edges for declarations nested in a query. A
scope-depth marker limits nested declarations to their enclosing query; the
existing module expansion bridge remains responsible for parameterized
definitions. The driver detects definitions anywhere in the filter and routes
zero-argument sources through the syntax/compiler/evaluator path.

Evidence: the focused fixture covers jq.test:775 and :789, including nested
shadowing and declaration-time visibility. The implementation deliberately
does not claim parameterized local definitions (:864) or generator-heavy
backtracking (:875), which require lexical call-frame and argument-stream
metadata beyond the current direct-body Call ABI.
