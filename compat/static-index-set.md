# Bounded static array-index numeric assignment

This shard covers root static `.[INDEX] = NUMBER` assignment for integer
indexes, including jq's negative-last-element and append-at-length behavior.
Dynamic indexes, nested paths, nonnumeric values, generators, and other
assignment operators remain deferred.
