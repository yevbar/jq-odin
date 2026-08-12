# Static object constructor source order

This bounded shard covers source-order serialization for static object keys and
the corresponding Cartesian stream order when static-key values are generators.
Dynamic/computed keys retain their existing reverse-dimension continuation;
duplicate-key replacement, dynamic assignment, and broader constructor forms
remain deferred.
