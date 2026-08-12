# Numeric slice-read compatibility shard

Read-only array slices support omitted bounds, negative bounds, and empty
results when the normalized start is past the end. Slice assignment and
deletion, string slices, and dynamic bounds remain deferred.

Evidence: `upstream/jq/tests/jq.test:466-470`.
