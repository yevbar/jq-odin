# Negative literal counts for skip and nth

The parser admits unary-negative numeric literals for `skip` and `nth`, and the
evaluator preserves jq's catchable diagnostics. Dynamic counts and unrelated
continuation forms remain deferred.
