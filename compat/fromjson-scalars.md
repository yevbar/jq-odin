# Scalar `fromjson` compatibility shard

The oracle anchor is `upstream/jq/tests/jq.test:106-108`.  This lane parses
JSON null, booleans, and numeric literals from strings.  Arrays, objects,
escaped JSON strings, whitespace, and malformed-input diagnostics remain
deferred because the eval package graph intentionally does not import `jq:json`.
