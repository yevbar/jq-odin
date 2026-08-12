# `map` binding compatibility shard

This shard covers bindings whose body is contained by a `map(...)` call. The
parser must keep `as $name | body` inside the call boundary; dynamic generators
and assignment/update forms remain deferred.
