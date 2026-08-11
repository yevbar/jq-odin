# sin/cos compatibility shard

This bounded shard covers the zero-argument scalar sine and cosine builtins for
numeric input. Non-number diagnostics, NaN/infinity handling, and broader jq
math-library behavior remain deferred.

Run with:

~~~sh
tools/compat/jq_compat.py \
  --tests compat/trig.jq.test \
  --skips compat/trig-skips.json \
  --oracle "$ORACLE" --candidate /absolute/path/to/jq-odin --show-passes
~~~

Implementation provenance: parser recognition is
src/syntax/parser.odin:653-658; numeric operations are
src/eval/evaluator.odin:1843-1847; expected cases are
compat/trig.jq.test:1-12.
