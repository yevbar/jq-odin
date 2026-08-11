# `explode` compatibility shard

This lane covers zero-argument `explode` for ASCII strings, producing an owned
array of byte-valued code points. Unicode code-point decoding, non-string
diagnostics, and generator forms remain deferred.
