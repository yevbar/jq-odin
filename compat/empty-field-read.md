# Empty-string field-read compatibility shard

Quoted empty-string keys use ordinary object indexing, while empty brackets
remain the array/object iterator. The fixture covers root and composed reads
and locks the distinction beside `.[]` in one expression.

Oracle evidence: `upstream/jq/src/parser.y:601-620` lowers bracket queries and
empty-bracket iteration separately; `upstream/jq/src/jv_aux.c:80-87` performs
object lookup for every string key.

Assignments, updates, `path`, dynamic indexes, and dynamic slice bounds remain
outside this read-only shard.
