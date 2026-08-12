# Bounded static object-field update

This shard covers only `.field |= . + NUMBER` on an object that already has a
numeric field. The syntax and program discriminants are append-only and encode
the static field name plus numeric spelling directly; they do not claim a
general jq path or update-continuation contract.

The first case is `upstream/jq/tests/jq.test:1212-1214`. Static array
iteration, nested and dynamic paths, missing-field construction, deletion via
`empty`, multi-output update filters, and the other assignment operators remain
deferred.
