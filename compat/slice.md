# Slice-read compatibility shard

Read-only array and UTF-8 string slices support omitted bounds, negative
bounds, and empty results when the normalized start is past the end. String
bounds are code-point indexes. Slice assignment and deletion, and dynamic
bounds remain deferred.

Evidence: `upstream/jq/tests/jq.test:466-470`.
