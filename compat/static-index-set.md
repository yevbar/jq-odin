# Bounded static array-index numeric assignment

This shard covers root static `.[INDEX] = NUMBER` assignment for integer
indexes, including jq's negative-last-element and append-at-length behavior.
Boolean, null, and string right-hand literals are also supported. Dynamic
indexes, nested paths, containers, generators, and other assignment operators
remain deferred.
