# `implode` compatibility shard

This lane covers zero-argument `implode` for arrays of integral ASCII code
points. It produces an owned string through the existing strings builder. UTF-8
code points, non-integral values, and diagnostic wording remain deferred.
