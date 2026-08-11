# `utf8bytelength` compatibility shard

This bounded shard covers the zero-argument scalar builtin, returning the
encoded UTF-8 byte count for strings. Non-string diagnostics and malformed
byte input remain deferred.

Run with:

```sh
tools/compat/jq_compat.py \
  --tests compat/utf8bytelength.jq.test \
  --skips compat/utf8bytelength-skips.json \
  --oracle "$ORACLE" --candidate /absolute/path/to/jq-odin --show-passes
```

Evidence: `upstream/jq/tests/jq.test:732` covers the multibyte case;
`compat/utf8bytelength.jq.test:1-9` records this bounded parity slice.
