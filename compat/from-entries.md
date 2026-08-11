# `from_entries` compatibility shard

This bounded lane converts arrays of `{key, value}` objects into an object in
input order. Alternate key spellings, malformed entries, and non-array inputs
remain deferred.
