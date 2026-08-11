# `implode` compatibility shard

This lane covers zero-argument `implode` for ASCII and Unicode code points. It
produces an owned UTF-8 string through the existing strings builder; `explode`
then returns Unicode codepoints rather than bytes. Negative, out-of-range, and
UTF-16-surrogate values map to U+FFFD, while positive fractions truncate toward
zero, matching `upstream/jq/tests/jq.test:2358-2361`.

Diagnostic wording and malformed UTF-8 input remain deferred.
