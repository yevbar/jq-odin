# Decision 0280: literal walk compatibility

Accept only the literal identity/scalar walk forms whose observable result is
equivalent to an existing stream. Do not claim recursive `walk(f)` semantics;
those require a post-order traversal frame and owned child reconstruction.
