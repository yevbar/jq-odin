# ascii_downcase/ascii_upcase compatibility shard

This bounded shard covers zero-argument ASCII case filters for string inputs.
Only bytes in the ASCII A-Z/a-z ranges are transformed; non-ASCII UTF-8 bytes
are preserved. Non-string diagnostics and locale-sensitive behavior remain
deferred.

Run with:

~~~sh
tools/compat/jq_compat.py \
  --tests compat/ascii-case.jq.test \
  --skips compat/ascii-case-skips.json \
  --oracle "$ORACLE" --candidate /absolute/path/to/jq-odin --show-passes
~~~

Implementation provenance: parser recognition is
src/syntax/parser.odin:656-659; evaluator transformation is
src/eval/evaluator.odin:1867-1897; expected cases are
compat/ascii-case.jq.test:1-12.
