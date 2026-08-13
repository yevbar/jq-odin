# Decision: preserve bounded function-call coverage while deferring recursion

The driver already expands zero-argument and parameterized non-recursive
definitions into parenthesized filter source before syntax parsing. This
provides correct caller-input and generator-stream behavior for `def f: .+1;
f` and `def f: ., .+1; f`, verified by `compat/function-definition-calls.jq.test`.

Do not extend textual expansion to recursive definitions. A recursive call
must become an evaluator activation frame with owned return continuation and
depth/error policy; otherwise expansion can recurse indefinitely or duplicate
stream state. This shard therefore records the working call boundary while
keeping recursion as the next shared Program/evaluator contract.
