# `tostring` compatibility shard

This bounded lane covers the zero-argument string form, which returns an owned
copy of the input string. Numeric, boolean, null, array, and object formatting
remain deferred.
