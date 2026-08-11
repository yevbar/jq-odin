# Native number-format compatibility shard

This shard covers the jq arithmetic case where binary-float noise would
otherwise leak into serialized output. Ordinary finite values are normalized
to fifteen significant decimal digits before the existing plain/scientific
threshold logic; infinities retain their exact max-f64 spelling.

The source case is `upstream/jq/tests/jq.test:653`. Broader decimal-context
and special-number behavior remain covered by the JSON package tests.
