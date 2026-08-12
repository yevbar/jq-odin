# String division

String division uses jq's separator semantics and returns an array of
segments, sharing the bounded string splitter implementation.

Oracle evidence: `upstream/jq/tests/jq.test:1607-1611`.
