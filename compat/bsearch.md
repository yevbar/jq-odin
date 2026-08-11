# Bounded numeric `bsearch` compatibility shard

This lane implements a single numeric literal needle against a sorted array,
returning the matching index or jq's negative insertion-point encoding. It
uses the existing value ordering comparator. Multi-needle generator calls,
object needles, dynamic arguments, and non-array diagnostics remain deferred;
those forms appear at `upstream/jq/tests/jq.test:1789-1801`.
