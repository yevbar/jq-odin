# Cartesian foreach generator

The focused case pins the common numeric form `foreach .[] / .[] as $i
(0; . + $i)`. jq evaluates the divided generator as a Cartesian product,
then applies the update to each value in right-major order. The Odin slice
materializes that numeric stream while the general continuation contract is
still pending.

The oracle case is from jq's generator semantics in
`upstream/jq/tests/jq.test:2496-2503` and a direct probe of the divided stream.
