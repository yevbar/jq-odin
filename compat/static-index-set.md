# Bounded static array-index numeric assignment

This shard covers root static `.[INDEX] = NUMBER` assignment for integer
indexes, including jq's negative-last-element and append-at-length behavior.
Boolean and null right-hand literals are also supported. Dynamic indexes,
nested paths, strings/containers, generators, and other assignment operators
remain deferred.
